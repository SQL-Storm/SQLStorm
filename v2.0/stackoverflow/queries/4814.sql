-- {"query": "4814.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 950}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY SUBSTR(u.DisplayName, 1, 1) ORDER BY u.LastAccessDate DESC) AS LastAccessRankByInitial
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
HighReputationUsers AS (
    SELECT UserId, DisplayName, Reputation, CreationDate
    FROM RankedUserActivity
    WHERE ReputationRank <= 100
),
RecentHighActivityPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS ActivityRank
    FROM Posts p
    JOIN HighReputationUsers u ON p.OwnerUserId = u.UserId
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365' DAY)
      AND p.PostTypeId = 1 -- Questions only
      AND p.AnswerCount > 0
      AND p.Score > 10
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName, p.LastActivityDate, p.AnswerCount
),
PostAnswerMetrics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        AVG(CAST(LENGTH(c.Text) AS DOUBLE PRECISION)) AS AvgCommentLength,
        COUNT(CASE WHEN c.UserId IS NOT NULL THEN c.Id ELSE NULL END) AS CommenterCount,
        COUNT(DISTINCT c.UserId) AS DistinctCommenterCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCommentCount,
        CASE
            WHEN COUNT(c.Id) > 0 THEN MAX(c.CreationDate)
            ELSE p.CreationDate
        END AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 -- Questions only
    GROUP BY p.Id, p.Title, p.CreationDate
)
SELECT
    rhap.PostId,
    rhap.Title AS QuestionTitle,
    rhap.OwnerDisplayName,
    rhap.PostScore,
    pam.AvgCommentLength,
    pam.CommenterCount,
    pam.DistinctCommenterCount,
    pam.PositiveScoreCommentCount,
    CASE
        WHEN pam.LastCommentDate IS NULL THEN 'No Comments'
        WHEN pam.LastCommentDate > (cast('2024-10-01' as date) - INTERVAL '7' DAY) THEN 'Recent'
        WHEN pam.LastCommentDate > (cast('2024-10-01' as date) - INTERVAL '30' DAY) THEN 'Within Month'
        ELSE 'Older'
    END AS CommentRecency,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rhap.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rhap.PostId AND ph.PostHistoryTypeId IN (10, 11)) AS CloseReopenEvents,
    (SELECT Name FROM PostTypes WHERE Id = 1) AS PostTypeName
FROM RecentHighActivityPosts rhap
JOIN PostAnswerMetrics pam ON rhap.PostId = pam.PostId
WHERE rhap.ActivityRank <= 50
  AND pam.AvgCommentLength BETWEEN 50 AND 500
  AND pam.DistinctCommenterCount >= 3
ORDER BY rhap.PostScore DESC, rhap.PostCreationDate ASC
LIMIT 100;