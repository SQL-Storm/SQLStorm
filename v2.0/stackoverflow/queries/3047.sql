-- {"query": "3047.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2674}
WITH
    UserActivity AS (
        SELECT
            u.Id                                            AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(pcnt.TotalPosts,0)                     AS TotalPosts,
            COALESCE(qcnt.QuestionPosts,0)                  AS QuestionPosts,
            COALESCE(acnt.AnswerPosts,0)                    AS AnswerPosts,
            COALESCE(vs.VoteScore,0)                        AS VoteScore,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)  AS RepRank
        FROM Users u
        LEFT JOIN (
            SELECT OwnerUserId, COUNT(*) AS TotalPosts
            FROM Posts
            GROUP BY OwnerUserId
        ) pcnt ON pcnt.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT OwnerUserId, COUNT(*) AS QuestionPosts
            FROM Posts
            WHERE PostTypeId = 1
            GROUP BY OwnerUserId
        ) qcnt ON qcnt.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT OwnerUserId, COUNT(*) AS AnswerPosts
            FROM Posts
            WHERE PostTypeId = 2
            GROUP BY OwnerUserId
        ) acnt ON acnt.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT p.OwnerUserId,
                   SUM(CASE v.VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END) AS VoteScore
            FROM Posts p
            LEFT JOIN Votes v ON v.PostId = p.Id
            GROUP BY p.OwnerUserId
        ) vs ON vs.OwnerUserId = u.Id
    ),

    RecentBadges AS (
        SELECT
            b.UserId,
            STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames,
            COUNT(*)                                        AS BadgeCount
        FROM Badges b
        WHERE b.Date >= (CAST('2024-10-01' AS date) - INTERVAL '90' DAY)
        GROUP BY b.UserId
    ),

    LatestCommentPerPost AS (
        SELECT
            c.PostId,
            c.Text          AS LatestComment,
            c.CreationDate
        FROM Comments c
        WHERE c.CreationDate = (
            SELECT MAX(c2.CreationDate)
            FROM Comments c2
            WHERE c2.PostId = c.PostId
        )
    ),

    TagStats AS (
        SELECT
            t.TagName,
            COUNT(p.Id)                                            AS QuestionCount,
            SUM(p.Score)                                           AS TotalScore,
            AVG(p.ViewCount)                                       AS AvgViews,
            ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC)          AS TagRank
        FROM Tags t
        JOIN Posts p
          ON p.Tags IS NOT NULL
         AND p.Tags LIKE '%' || t.TagName || '%'
        WHERE p.PostTypeId = 1
        GROUP BY t.TagName
        HAVING COUNT(p.Id) > 50
    )

SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.RepRank,
    ua.TotalPosts,
    ua.QuestionPosts,
    ua.AnswerPosts,
    ua.VoteScore,
    COALESCE(rb.BadgeNames, 'No recent badges') AS RecentBadges,
    COALESCE(rb.BadgeCount,0)                    AS RecentBadgeCount,
    CASE
        WHEN ua.TotalPosts = 0 THEN NULL
        ELSE ROUND(CAST(ua.VoteScore AS NUMERIC) / ua.TotalPosts, 2)
    END                                         AS AvgVotePerPost,
    lc.LatestComment,
    lc.CreationDate AS LatestCommentDate,
    CAST(NULL AS INTEGER) AS TagRank
FROM UserActivity ua
LEFT JOIN RecentBadges rb
  ON rb.UserId = ua.UserId
LEFT JOIN LatestCommentPerPost lc
  ON lc.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ua.UserId
          AND p.PostTypeId = 2
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
WHERE ua.Reputation > 1000

UNION ALL

SELECT
    CAST(NULL AS BIGINT) AS UserId,
    CAST(NULL AS TEXT)   AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS RepRank,
    CAST(NULL AS INTEGER) AS TotalPosts,
    CAST(NULL AS INTEGER) AS QuestionPosts,
    CAST(NULL AS INTEGER) AS AnswerPosts,
    CAST(NULL AS BIGINT)  AS VoteScore,
    CAST(NULL AS TEXT)    AS RecentBadges,
    CAST(NULL AS INTEGER) AS RecentBadgeCount,
    CAST(NULL AS NUMERIC) AS AvgVotePerPost,
    CAST(NULL AS TEXT)    AS LatestComment,
    CAST(NULL AS TIMESTAMP) AS LatestCommentDate,
    CAST(NULL AS INTEGER) AS TagRank
FROM (SELECT 1) AS dummy

UNION ALL

SELECT
    CAST(NULL AS BIGINT)           AS UserId,
    ts.TagName                     AS DisplayName,
    CAST(NULL AS INTEGER)          AS Reputation,
    CAST(NULL AS INTEGER)          AS RepRank,
    CAST(NULL AS INTEGER)          AS TotalPosts,
    ts.QuestionCount               AS QuestionPosts,
    CAST(NULL AS INTEGER)          AS AnswerPosts,
    ts.TotalScore                  AS VoteScore,
    CAST(NULL AS TEXT)             AS RecentBadges,
    CAST(NULL AS INTEGER)          AS RecentBadgeCount,
    CAST(NULL AS NUMERIC)          AS AvgVotePerPost,
    CAST(NULL AS TEXT)             AS LatestComment,
    CAST(NULL AS TIMESTAMP)        AS LatestCommentDate,
    ts.TagRank                     AS TagRank
FROM TagStats ts

ORDER BY RepRank NULLS LAST, TagRank NULLS LAST
LIMIT 100;