module.exports = [

  // Global ignores (must be the first entry)
  {
    ignores: [
      'node_modules/',
      'ios/',
      'android/',
      '.expo/',
      'dist/',
      'build/',
      '**/build/**',
      '*.config.js',
      'metro.config.js',
      'eslint.config.js',
      'plugins/**/build/',
      'modules/**/plugin/build/',
      'modules/witnesscalculator/android/',
      'modules/rapidsnark-wrp/android/',
    ],
  },

  // Official Expo-recommended preset. bundles core + TypeScript + React + Expo rules
  ...require('eslint-config-expo/flat'),

  // Disable stylistic rules that would config with our prettier setup
  // (we run `npm run format` separately for formatting).
  require('eslint-config-prettier'),

  // Project-wide rules (any file).
  {
    rules: {
      'no-console': 'warn',
    },
  },

  // files that run on node context
  {
    files: ['scripts/**/*.{js,mjs,cjs}'],
    languageOptions: {
      globals: {
        ...require('globals').node,
      },
    },
  },

  {
    files: ['**/*.ts', '**/*.tsx'],
    plugins: {
      '@typescript-eslint': require('@typescript-eslint/eslint-plugin'),
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },
];
