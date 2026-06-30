package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"flag"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-contrib/sessions"
	"github.com/gin-contrib/sessions/cookie"
	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/joho/godotenv"
	"github.com/vaccs/irvis-go/internal/middleware"
)

func getenvInt(key string, def int) int {
	val := os.Getenv(key)
	if val == "" {
		return def
	}
	n, err := strconv.Atoi(val)
	if err != nil {
		return def
	}
	return n
}

// Helper to hash password
func sha256sum(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

// Helper to get user ID from session
func getSessionUserID(c *gin.Context) (int, bool) {
	sess := sessions.Default(c)
	uid, ok := sess.Get("user_id").(int)
	return uid, ok
}

// Helper to cleanup stale login sessions
func cleanupStaleLogins(db *sql.DB) {
	// Reset is_logged_in to FALSE for all users
	// This can be called periodically or on server restart
	result, err := db.Exec("UPDATE users SET is_logged_in=FALSE WHERE is_logged_in=TRUE")
	if err != nil {
		log.Printf("Error cleaning up stale logins: %v", err)
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected > 0 {
		log.Printf("Cleaned up %d stale login sessions", rowsAffected)
	}
}

// Authentication middleware for protected /irvis routes
func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check session for authentication
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		if userID == nil {
			path := c.Request.URL.Path
			log.Printf("Unauthenticated access to %s from %s, redirecting to login", path, c.ClientIP())
			c.Redirect(http.StatusFound, "/irvis/login?error=Please+login+to+access+this+page")
			c.Abort()
			return
		}

		path := c.Request.URL.Path
		log.Printf("Authenticated user %v accessing %s", userID, path)
		c.Next()
	}
}

// Optional authentication middleware - doesn't redirect if not authenticated
func optionalAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Just check session but don't enforce authentication
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		path := c.Request.URL.Path
		if userID != nil {
			log.Printf("Authenticated user %v accessing %s", userID, path)
		} else {
			log.Printf("Unauthenticated access to %s from %s (allowed)", path, c.ClientIP())
		}
		c.Next()
	}
}

// Admin-only middleware for administrative functions
func adminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check session for authentication first
		sess := sessions.Default(c)
		userID := sess.Get("user_id")
		isAdmin := sess.Get("is_admin")

		if userID == nil {
			path := c.Request.URL.Path
			log.Printf("Unauthenticated access to admin route %s from %s", path, c.ClientIP())
			c.Redirect(http.StatusFound, "/irvis/login?error=Please+login+to+access+this+page")
			c.Abort()
			return
		}

		// Check if user is admin
		if isAdmin == nil || !isAdmin.(bool) {
			path := c.Request.URL.Path
			log.Printf("Non-admin user %v attempted to access %s", userID, path)
			c.Redirect(http.StatusFound, "/irvis?error=Access+denied.+Administrator+privileges+required.")
			c.Abort()
			return
		}

		path := c.Request.URL.Path
		log.Printf("Admin user %v accessing %s", userID, path)
		c.Next()
	}
}

func main() {
	modeDefault := strings.ToLower(os.Getenv("APP_MODE"))
	if modeDefault == "" {
		modeDefault = "native"
	}

	mode := flag.String("mode", modeDefault, "runtime mode: native or docker")
	flag.Parse()

	runtimeMode := strings.ToLower(strings.TrimSpace(*mode))
	if runtimeMode != "native" && runtimeMode != "docker" {
		log.Fatalf("Invalid -mode value %q. Allowed values: native, docker", runtimeMode)
	}

	// Explicitly load .env file
	if err := godotenv.Load(".env"); err != nil {
		log.Printf("Warning: .env file not loaded: %v", err)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	serverProtocol := strings.ToLower(os.Getenv("SERVER_PROTOCOL"))
	if serverProtocol == "" {
		if runtimeMode == "docker" {
			serverProtocol = "http"
		} else {
			serverProtocol = "https"
		}
	}
	if serverProtocol != "http" && serverProtocol != "https" {
		log.Fatalf("SERVER_PROTOCOL must be 'http' or 'https', got %q", serverProtocol)
	}

	tlsCert := os.Getenv("TLS_CERT_FILE")
	tlsKey := os.Getenv("TLS_KEY_FILE")
	if serverProtocol == "https" && (tlsCert == "" || tlsKey == "") {
		log.Fatal("TLS_CERT_FILE and TLS_KEY_FILE must be set when SERVER_PROTOCOL=https")
	}

	dbName := os.Getenv("DB_NAME")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbHost := os.Getenv("DB_HOST")
	if dbHost == "" {
		if runtimeMode == "docker" {
			dbHost = "mysql"
		} else {
			dbHost = "localhost"
		}
	}
	dbPort := os.Getenv("DB_PORT")
	if dbPort == "" {
		dbPort = "3306"
	}

	log.Printf("Runtime mode: %s", runtimeMode)

	maxOpen := getenvInt("MAX_OPEN_CONNS", 20)
	maxIdle := getenvInt("MAX_IDLE_CONNS", 10)
	maxLifetime := getenvInt("CONN_MAX_LIFETIME", 3600) // seconds

	log.Printf("DB config: name=%s user=%s", dbName, dbUser)
	log.Printf("Pool config: maxOpen=%d maxIdle=%d maxLifetime=%ds", maxOpen, maxIdle, maxLifetime)

	// Build DSN and connect to MySQL
	dsn := dbUser + ":" + dbPassword + "@tcp(" + dbHost + ":" + dbPort + ")/" + dbName + "?parseTime=true"
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("Failed to open DB: %v", err)
	}
	// Connection pooling settings
	db.SetMaxOpenConns(maxOpen)
	db.SetMaxIdleConns(maxIdle)
	db.SetConnMaxLifetime(time.Duration(maxLifetime) * time.Second)

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to connect to DB: %v", err)
	}
	log.Printf("Connected to MySQL database '%s' as user '%s'", dbName, dbUser)

	// Clean up any stale login sessions on server startup
	cleanupStaleLogins(db)

	r := gin.Default()

	// Session middleware
	store := cookie.NewStore([]byte("super-secret-key"))
	store.Options(sessions.Options{
		MaxAge:   86400, // 1 day in seconds
		HttpOnly: true,
		Secure:   serverProtocol == "https",
	})
	r.Use(sessions.Sessions("irvis_session", store))

	// CORS
	r.Use(middleware.CORS())

	// Health check
	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Root route - redirect to main application
	r.GET("/", func(c *gin.Context) {
		c.Redirect(http.StatusFound, "/irvis")
	})

	// Create public route group for /irvis routes (no auth required)
	irvisPublic := r.Group("/irvis")

	// API endpoint to check user authentication and admin status (public with optional auth)
	irvisPublic.GET("/api/user", optionalAuthMiddleware(), func(c *gin.Context) {
		sess := sessions.Default(c)
		userID := sess.Get("user_id")
		email := sess.Get("email")
		isAdmin := sess.Get("is_admin")

		if userID == nil {
			// Return 401 for unauthenticated users
			c.JSON(http.StatusUnauthorized, gin.H{
				"authenticated": false,
				"error":         "Not authenticated",
			})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"authenticated": true,
			"user_id":       userID,
			"email":         email,
			"is_admin":      isAdmin,
		})
	})

	// Logout routes (public but require authentication to do anything useful)
	irvisPublic.POST("/logout", func(c *gin.Context) {
		log.Printf("POST /irvis/logout from %s", c.ClientIP())
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		if userID != nil {
			// Update database to set is_logged_in=FALSE
			_, err := db.Exec("UPDATE users SET is_logged_in=FALSE WHERE id=?", userID)
			if err != nil {
				log.Printf("Error updating logout status for user %v: %v", userID, err)
			} else {
				log.Printf("User %v logged out, database updated", userID)
			}
		}

		// Clear session
		sess.Clear()
		sess.Save()

		c.Redirect(http.StatusFound, "/irvis")
	})

	// GET logout route for logout links
	irvisPublic.GET("/logout", func(c *gin.Context) {
		log.Printf("GET /irvis/logout from %s", c.ClientIP())
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		if userID != nil {
			// Update database to set is_logged_in=FALSE
			_, err := db.Exec("UPDATE users SET is_logged_in=FALSE WHERE id=?", userID)
			if err != nil {
				log.Printf("Error updating logout status for user %v: %v", userID, err)
			} else {
				log.Printf("User %v logged out via GET, database updated", userID)
			}
		}

		// Clear session
		sess.Clear()
		sess.Save()

		c.Redirect(http.StatusFound, "/irvis")
	})

	// Serve static files for /irvis/visual (Flutter web app) - public with cache control
	irvisPublic.GET("/visual/*filepath", func(c *gin.Context) {
		// Add cache control headers for Flutter web app
		// Allow short-term caching but enable revalidation
		c.Header("Cache-Control", "public, max-age=300, must-revalidate")
		c.Header("X-Content-Type-Options", "nosniff")

		// For HTML files, use no-cache to ensure fresh content
		filepath := c.Param("filepath")
		if filepath == "/" || filepath == "/index.html" {
			c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
			c.Header("Pragma", "no-cache")
			c.Header("Expires", "0")
		}

		c.FileFromFS(c.Request.URL.Path[len("/irvis/visual"):], http.Dir("./visual"))
	})

	// Main /irvis route with optional authentication - serve home page
	irvisPublic.GET("", optionalAuthMiddleware(), func(c *gin.Context) {
		log.Printf("GET /irvis accessed from %s", c.ClientIP())
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		// Add cache control headers to prevent stale page loads
		c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
		c.Header("Pragma", "no-cache")
		c.Header("Expires", "0")

		// Serve the home.html page for both authenticated and unauthenticated users
		content, err := os.ReadFile("./irvis/html/home.html")
		if err != nil {
			log.Printf("Error reading home.html: %v", err)
			c.String(http.StatusInternalServerError, "Error reading home.html: %v", err)
			return
		}

		if userID != nil {
			log.Printf("Serving home page to authenticated user %v", userID)
		} else {
			log.Printf("Serving home page to unauthenticated user")
		}
		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, string(content))
	})

	// Create protected route group for /irvis routes
	irvisGroup := r.Group("/irvis")
	irvisGroup.Use(authMiddleware())

	// Serve login page for GET /irvis/login (public)
	irvisPublic.GET("/login", func(c *gin.Context) {
		log.Printf("GET /irvis/login accessed from %s", c.ClientIP())

		content, err := os.ReadFile("./irvis/html/login.html")
		if err != nil {
			log.Printf("Error reading login.html: %v", err)
			c.String(http.StatusInternalServerError, "Error reading login.html: %v", err)
			return
		}

		log.Printf("Successfully serving login.html")
		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, string(content))
	})

	// Handle login form POST (public)
	irvisPublic.POST("/login", func(c *gin.Context) {
		log.Printf("POST /irvis/login from %s", c.ClientIP())
		login := c.PostForm("login")
		password := c.PostForm("password")

		if login == "" || password == "" {
			log.Printf("Missing credentials")
			c.Redirect(http.StatusFound, "/irvis/login?error=Missing+credentials")
			return
		}

		// Hash password (SHA256)
		hashed := sha256sum(password)

		var userID int
		var isAdmin bool
		var actualEmail string

		// Try to find user by email OR username
		row := db.QueryRow("SELECT id, email, is_admin FROM users WHERE (email=? OR username=?) AND hashed_password=?", login, login, hashed)
		if err := row.Scan(&userID, &actualEmail, &isAdmin); err != nil {
			log.Printf("Invalid credentials for login: %s", login)
			c.Redirect(http.StatusFound, "/irvis/login?error=Invalid+credentials")
			return
		}

		// Set is_logged_in flag
		_, _ = db.Exec("UPDATE users SET is_logged_in=TRUE WHERE id=?", userID)

		// Set session with user details
		sess := sessions.Default(c)
		sess.Set("user_id", userID)
		sess.Set("email", actualEmail)
		sess.Set("is_admin", isAdmin)
		sess.Save()

		log.Printf("User %s (ID: %d, Admin: %v) authenticated successfully", actualEmail, userID, isAdmin)
		c.Redirect(http.StatusFound, "/irvis")
	})

	// Protected GET /irvis/issue route
	irvisGroup.GET("/issue", func(c *gin.Context) {
		log.Printf("GET /irvis/issue accessed from %s", c.ClientIP())
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		// Serve the issue.html file for authenticated users
		content, err := os.ReadFile("./irvis/html/issue.html")
		if err != nil {
			log.Printf("Error reading issue.html: %v", err)
			c.String(http.StatusInternalServerError, "Error reading issue.html: %v", err)
			return
		}

		log.Printf("Serving issue.html to authenticated user %v", userID)
		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, string(content))
	})

	// POST /irvis/issue to create GitHub issue
	irvisGroup.POST("/issue", func(c *gin.Context) {
		log.Printf("POST /irvis/issue from %s", c.ClientIP())
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		title := c.PostForm("title")
		body := c.PostForm("body")
		repo := c.PostForm("repo")
		if title == "" || body == "" || repo == "" {
			log.Printf("Missing form data from user %v", userID)
			c.Redirect(http.StatusFound, "/irvis/issue?error=Missing+title+description+or+repo")
			return
		}
		if repo != "irvis-go" && repo != "irvis_flutter" {
			log.Printf("Invalid repo selection '%s' from user %v", repo, userID)
			c.Redirect(http.StatusFound, "/irvis/issue?error=Invalid+repo+selection")
			return
		}

		// Create GitHub issue
		githubToken := os.Getenv("GITHUB_TOKEN")
		if githubToken == "" {
			c.Redirect(http.StatusFound, "/irvis/issue?error=GitHub+token+not+configured")
			return
		}
		owner := "vaccs"
		apiURL := "https://api.github.com/repos/" + owner + "/" + repo + "/issues"

		client := &http.Client{Timeout: 10 * time.Second}
		reqBody := `{"title":"` + title + `","body":"` + body + `"}`
		req, err := http.NewRequest("POST", apiURL, strings.NewReader(reqBody))
		if err != nil {
			c.Redirect(http.StatusFound, "/irvis/issue?error=Failed+to+create+request")
			return
		}
		req.Header.Set("Authorization", "token "+githubToken)
		req.Header.Set("Accept", "application/vnd.github+json")
		req.Header.Set("Content-Type", "application/json")

		resp, err := client.Do(req)
		if err != nil {
			c.Redirect(http.StatusFound, "/irvis/issue?error=GitHub+API+error")
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode != 201 {
			c.Redirect(http.StatusFound, "/irvis/issue?error=Failed+to+create+issue")
			return
		}

		c.Redirect(http.StatusFound, "/irvis/issue?success=Issue+submitted+successfully")
	})

	// Change Password routes (requires authentication)
	irvisGroup.GET("/change_password", func(c *gin.Context) {
		log.Printf("GET /irvis/change_password accessed from %s", c.ClientIP())

		content, err := os.ReadFile("./irvis/html/change_password.html")
		if err != nil {
			log.Printf("Error reading change_password.html: %v", err)
			c.String(http.StatusInternalServerError, "Error reading change_password.html: %v", err)
			return
		}

		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, string(content))
	})

	irvisGroup.POST("/change_password", func(c *gin.Context) {
		log.Printf("POST /irvis/change_password from %s", c.ClientIP())
		sess := sessions.Default(c)
		userID := sess.Get("user_id")

		currentPassword := c.PostForm("current_password")
		newPassword := c.PostForm("new_password")
		confirmPassword := c.PostForm("confirm_password")

		// Validate input
		if currentPassword == "" || newPassword == "" || confirmPassword == "" {
			log.Printf("Missing password fields from user %v", userID)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=All+fields+are+required")
			return
		}

		// Check password length
		if len(newPassword) < 6 {
			log.Printf("New password too short from user %v", userID)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=Password+must+be+at+least+6+characters")
			return
		}

		// Check if passwords match
		if newPassword != confirmPassword {
			log.Printf("Password mismatch from user %v", userID)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=Passwords+do+not+match")
			return
		}

		// Check if new password is different from current
		if currentPassword == newPassword {
			log.Printf("New password same as current from user %v", userID)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=New+password+must+be+different")
			return
		}

		// Verify current password
		hashedCurrent := sha256sum(currentPassword)
		var storedHash string
		err := db.QueryRow("SELECT hashed_password FROM users WHERE id=?", userID).Scan(&storedHash)
		if err != nil {
			log.Printf("Error querying user %v: %v", userID, err)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=Database+error")
			return
		}

		if hashedCurrent != storedHash {
			log.Printf("Incorrect current password for user %v", userID)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=Current+password+is+incorrect")
			return
		}

		// Update password
		hashedNew := sha256sum(newPassword)
		_, err = db.Exec("UPDATE users SET hashed_password=? WHERE id=?", hashedNew, userID)
		if err != nil {
			log.Printf("Error updating password for user %v: %v", userID, err)
			c.Redirect(http.StatusFound, "/irvis/change_password?error=Failed+to+update+password")
			return
		}

		log.Printf("Password changed successfully for user %v", userID)
		c.Redirect(http.StatusFound, "/irvis/change_password?success=Password+changed+successfully")
	})

	// Admin-only routes
	adminGroup := r.Group("/irvis")
	adminGroup.Use(adminMiddleware())

	// GET /irvis/add_user - Display add user form (admin only)
	adminGroup.GET("/add_user", func(c *gin.Context) {
		log.Printf("GET /irvis/add_user accessed by admin from %s", c.ClientIP())

		content, err := os.ReadFile("./irvis/html/add_user.html")
		if err != nil {
			log.Printf("Error reading add_user.html: %v", err)
			c.String(http.StatusInternalServerError, "Error reading add_user.html: %v", err)
			return
		}

		c.Header("Content-Type", "text/html; charset=utf-8")
		c.String(http.StatusOK, string(content))
	})

	// POST /irvis/add_user - Process add user form (admin only)
	adminGroup.POST("/add_user", func(c *gin.Context) {
		log.Printf("POST /irvis/add_user from admin %s", c.ClientIP())

		username := c.PostForm("username")
		email := c.PostForm("email")
		password := c.PostForm("password")
		confirmPassword := c.PostForm("confirm_password")
		isAdmin := c.PostForm("is_admin") == "true"

		// Validate required fields
		if username == "" || email == "" || password == "" {
			log.Printf("Missing required fields in add user form")
			c.Redirect(http.StatusFound, "/irvis/add_user?error=All+fields+are+required")
			return
		}

		// Validate password confirmation
		if password != confirmPassword {
			log.Printf("Password confirmation mismatch")
			c.Redirect(http.StatusFound, "/irvis/add_user?error=Passwords+do+not+match")
			return
		}

		// Check if username or email already exists
		var existingCount int
		err := db.QueryRow("SELECT COUNT(*) FROM users WHERE username=? OR email=?", username, email).Scan(&existingCount)
		if err != nil {
			log.Printf("Database error checking existing user: %v", err)
			c.Redirect(http.StatusFound, "/irvis/add_user?error=Database+error")
			return
		}

		if existingCount > 0 {
			log.Printf("Username or email already exists: %s, %s", username, email)
			c.Redirect(http.StatusFound, "/irvis/add_user?error=Username+or+email+already+exists")
			return
		}

		// Hash password
		hashedPassword := sha256sum(password)

		// Insert new user
		_, err = db.Exec("INSERT INTO users (username, email, hashed_password, is_logged_in, is_admin) VALUES (?, ?, ?, FALSE, ?)",
			username, email, hashedPassword, isAdmin)
		if err != nil {
			log.Printf("Failed to insert new user: %v", err)
			c.Redirect(http.StatusFound, "/irvis/add_user?error=Failed+to+create+user")
			return
		}

		log.Printf("Admin successfully created user: %s (email: %s, admin: %v)", username, email, isAdmin)
		c.Redirect(http.StatusFound, "/irvis/add_user?success=User+created+successfully")
	})

	if serverProtocol == "http" {
		log.Printf("Server listening with HTTP on :%s", port)
		if err := r.Run(":" + port); err != nil {
			log.Fatal(err)
		}
		return
	}

	log.Printf("Server listening with HTTPS on :%s", port)
	if err := r.RunTLS(":"+port, tlsCert, tlsKey); err != nil {
		log.Fatal(err)
	}
}
