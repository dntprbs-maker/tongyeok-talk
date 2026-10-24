// Template for the Translate API URL
// Format: 'https://translate.example.com'
// Replace 'example.com' with your actual domain.
// You can self-host using LibreTranslate or use a paid service.

// Setup Instructions:
// 1. Copy lib/secrets_sample.dart to lib/secrets.dart
// 2. Fill in your actual translation API URL below
// 3. Make sure lib/secrets.dart is not committed (it's already in .gitignore)

// CI/CD with GitHub Actions:
// - For Firebase Hosting deployments via GitHub Actions, you can inject this file automatically.
// - In your workflow YAML (e.g., .github/workflows/firebase-hosting-merge.yml), add this step:
//     echo "${{ secrets.SECRETS_DART_CONTENT }}" > lib/secrets.dart
// - Store your secrets.dart content as a GitHub Actions secret named `SECRETS_DART_CONTENT`.
//   Example content for the secret (all on one line, with escaped quotes):
//     const String kTranslateApiUrl = 'https://translate.yourdomain.com';
// - This keeps your secret API URL out of version control, while still enabling builds and deploys.

const String kTranslateApiUrl = 'YOUR_TRANSLATE_API_URL_HERE';
