-- {"query": "2961.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1379}
WITH RecursiveUserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(b.Date) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostAnswersCTE AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score AS AnswerScore,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        COALESCE(pa.AnswerCount, 0) AS AnswerCount,
        COALESCE(pa.BestAnswerScore, 0) AS BestAnswerScore,
        q.ClosedDate,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS PopularityRank
    FROM Posts q
    LEFT JOIN (
        SELECT
            ParentId,
            COUNT(*) AS AnswerCount,
            MAX(Score) AS BestAnswerScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) pa ON pa.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
LatestComments AS (
    SELECT
        c.PostId,
        c.Id AS CommentId,
        c.Text AS CommentText,
        c.UserId AS CommentUserId,
        c.CreationDate AS CommentDate,
        u.DisplayName AS CommentUserDisplayName
    FROM (
        SELECT
            PostId,
            MAX(CreationDate) AS MaxCreationDate
        FROM Comments
        GROUP BY PostId
    ) mc
    JOIN Comments c ON c.PostId = mc.PostId AND c.CreationDate = mc.MaxCreationDate
    LEFT JOIN Users u ON u.Id = c.UserId
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(p.CreationDate) AS LatestPostDate,
        MAX(c.CreationDate) AS LatestCommentDate,
        COALESCE(
            GREATEST(
                MAX(p.CreationDate),
                MAX(c.CreationDate)
            ),
            u.LastAccessDate
        ) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.LastAccessDate
),
DuplicatePosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name AS LinkTypeName,
        pq.Title AS OriginalTitle,
        pr.Title AS DuplicateTitle
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts pq ON pq.Id = pl.PostId
    JOIN Posts pr ON pr.Id = pl.RelatedPostId
    WHERE lt.Name = 'Duplicate'
),
CorrelatedRecentActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate > u.CreationDate) AS NextPostAfterCreation,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score > 10 AND p.CreationDate BETWEEN u.CreationDate AND CAST('2024-10-01 12:34:56' AS TIMESTAMP)) AS HighScorePostsAfterCreation
    FROM Users u
),
CombinedActivity AS (
    SELECT
        ru.UserId,
        ru.LatestPostDate,
        ru.LatestCommentDate,
        ru.LastActivityDate,
        rca.NextPostAfterCreation,
        rca.HighScorePostsAfterCreation
    FROM UserRecentActivity ru
    LEFT JOIN CorrelatedRecentActivity rca ON rca.Id = ru.UserId
)
SELECT 
    q.QuestionId,
    q.Title,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.BestAnswerScore,
    ( 'Tags: ' || COALESCE(q.Tags, 'No Tags') || ' | ' || 'Closed: ' || CASE WHEN q.ClosedDate IS NOT NULL THEN 'Yes' ELSE 'No' END || ' | ' || 'Popularity Rank: #' || CAST(q.PopularityRank AS VARCHAR) ) AS QuestionMetadata,
    u.DisplayName AS QuestionOwner,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    lc.CommentText AS LatestCommentOnQuestion,
    lc.CommentUserDisplayName,
    da.PostId AS DuplicatePostId,
    da.DuplicateTitle,
    da.CreationDate AS DuplicateMarkedDate,
    ca.NextPostAfterCreation,
    ca.HighScorePostsAfterCreation,
    CASE 
        WHEN q.AnswerCount = 0 THEN NULL
        ELSE (
            SELECT
                '[' || STRING_AGG(
                    '{' ||
                    '"AnswerId":' || '"' || ans.AnswerId || '"' || ',' ||
                    '"Score":' || '"' || ans.AnswerScore || '"' || ',' ||
                    '"IsAccepted":' || '"' || (CASE WHEN acc.Id IS NOT NULL AND acc.Id = ans.AnswerId THEN '1' ELSE '0' END) || '"' ||
                    '}'
                    , ','
                ) || ']'
            FROM PostAnswersCTE ans
            LEFT JOIN Posts acc ON acc.ParentId = ans.QuestionId AND acc.Id = acc.Id
            WHERE ans.QuestionId = q.QuestionId AND ans.AnswerRank <= 3
        )
    END AS Top3AnswersSummary
FROM QuestionStats q
LEFT JOIN Users u ON u.Id = q.QuestionOwnerId
LEFT JOIN RecursiveUserBadgeCounts ub ON ub.UserId = u.Id AND ub.BadgeRank = 1
LEFT JOIN LatestComments lc ON lc.PostId = q.QuestionId
LEFT JOIN DuplicatePosts da ON da.PostId = q.QuestionId
LEFT JOIN CombinedActivity ca ON ca.UserId = u.Id
WHERE (q.ViewCount > 5000
       OR q.AnswerCount > 5
       OR q.QuestionScore > 50)
  AND (COALESCE(ub.GoldBadges,0) + COALESCE(ub.SilverBadges,0) + COALESCE(ub.BronzeBadges,0)) > 0
ORDER BY q.QuestionScore DESC, q.ViewCount DESC
LIMIT 100;