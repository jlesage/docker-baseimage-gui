package log

import (
	"os"
	"log"
	"errors"
	"strings"
)

const (
	FatalLevel = iota
	ErrorLevel
	WarnLevel
	InfoLevel
	DebugLevel
)

var (
	FatalLogger   *log.Logger
	ErrorLogger   *log.Logger
	WarningLogger *log.Logger
	GenericLogger *log.Logger

	Level int
)

func Debug(v ...interface{}) {
	if Level >= DebugLevel {
		GenericLogger.Println(v...)
	}
}

func Debugf(format string, v ...interface{}) {
	if Level >= DebugLevel {
		GenericLogger.Printf(format, v...)
	}
}

func Info(v ...interface{}) {
	if Level >= InfoLevel {
		GenericLogger.Println(v...)
	}
}

func Infof(format string, v ...interface{}) {
	if Level >= InfoLevel {
		GenericLogger.Printf(format, v...)
	}
}

func Warn(v ...interface{}) {
	if Level >= WarnLevel {
		WarningLogger.Println(v...)
	}
}

func Warnf(format string, v ...interface{}) {
	if Level >= WarnLevel {
		WarningLogger.Printf(format, v...)
	}
}

func Error(v ...interface{}) {
	if Level >= ErrorLevel {
		ErrorLogger.Println(v...)
	}
}

func Errorf(format string, v ...interface{}) {
	if Level >= ErrorLevel {
		ErrorLogger.Printf(format, v...)
	}
}

func Fatal(v ...interface{}) {
	FatalLogger.Println(v...)
	os.Exit(1)
}

func Fatalf(format string, v ...interface{}) {
	FatalLogger.Printf(format, v...)
	os.Exit(1)
}

func Println(v ...interface{}) {
	GenericLogger.Println(v...)
}

func Printf(format string, v ...interface{}) {
	GenericLogger.Printf(format, v...)
}

func SetLevel(levelName string) error {
	levelName = strings.ToLower(levelName)

	if levelName == "fatal" {
		Level = FatalLevel
	} else if levelName == "error" || levelName == "err" {
		Level = ErrorLevel
	} else if levelName == "warning" || levelName == "warn" {
		Level = WarnLevel
	} else if levelName == "info" {
		Level = InfoLevel
	} else if levelName == "debug" {
		Level = DebugLevel
	} else {
		return errors.New("invalid log level")
	}
	return nil
}

func init() {
	FatalLogger = log.New(os.Stderr, "FATAL: ", 0)
	ErrorLogger = log.New(os.Stderr, "ERROR: ", 0)
	WarningLogger = log.New(os.Stdout, "WARNING: ", 0)
	GenericLogger = log.New(os.Stdout, "", 0)

	Level = ErrorLevel
}
