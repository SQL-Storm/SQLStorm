WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN 1 END) AS TitleEdits,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 END) DESC) AS ReputationRank,
        RANK() OVER (PARTITION BY u.Id ORDER BY u.CreationDate ASC) AS UserCreationRank,
        u.CreationDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.DisplayName IS NOT NULL AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostScoreRank,
        p.CreationDate,
        p.Score
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 1
      AND p.Title IS NOT NULL
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY)
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.AnswerCount, p.Score, p.CreationDate
)
SELECT
    COALESCE(r.DisplayName, 'Anonymous') AS UserDisplayName,
    r.Reputation,
    r.BodyEdits,
    r.TitleEdits,
    r.UpvotesReceived,
    r.DownvotesReceived,
    pe.PostId,
    pe.Title AS PostTitle,
    pe.CommentCount,
    pe.UpvoteCount AS PostUpvotes,
    pe.DownvoteCount AS PostDownvotes,
    pe.AnswerCount AS PostAnswerCount,
    r.ReputationRank,
    pe.PostScoreRank,
    CASE
        WHEN r.Reputation > 10000 THEN 'Expert'
        WHEN r.Reputation > 1000 THEN 'Experienced'
        ELSE 'Beginner'
    END AS ReputationLevel,
    CASE
        WHEN POSITION('SQL' IN pe.Title) > 0 THEN 'SQL Related'
        WHEN POSITION('Performance' IN pe.Title) > 0 THEN 'Performance Tuning'
        ELSE 'Other'
    END AS TitleCategory,
    CAST(EXTRACT(YEAR FROM r.CreationDate) AS VARCHAR) || '-' ||
    LPAD(CAST(EXTRACT(MONTH FROM r.CreationDate) AS VARCHAR), 2, '0') || '-' ||
    LPAD(CAST(EXTRACT(DAY FROM r.CreationDate) AS VARCHAR), 2, '0') AS UserCreationDate,
    CASE
        WHEN ph.Comment IS NOT NULL AND ph.PostHistoryTypeId = 10 THEN ph.Comment
        ELSE 'No Close Reason'
    END AS CloseReasonComment,
    r.UserId
FROM RankedUserActivity r
FULL OUTER JOIN PostEngagement pe ON r.UserId = pe.OwnerUserId
LEFT JOIN PostHistory ph ON pe.PostId = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE (r.ReputationRank <= 50) OR (pe.PostId IS NOT NULL)
ORDER BY r.Reputation DESC, pe.PostScoreRank ASC, r.UserId;