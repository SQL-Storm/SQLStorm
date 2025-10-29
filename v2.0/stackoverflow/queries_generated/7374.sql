-- {"query": "7374.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1916} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) AS DaysSinceLastPost,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(p.Score) AS FLOAT) / COUNT(DISTINCT p.Id)
            ELSE 0 
        END AS AvgScorePerPost,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p2 
             WHERE p2.OwnerUserId = u.Id 
               AND p2.PostTypeId = 1 
               AND p2.AcceptedAnswerId IS NOT NULL), 0
        ) AS AcceptedAnswers,
        STRING_AGG(DISTINCT CASE 
            WHEN p.PostTypeId = 1 THEN p.Title 
            ELSE NULL 
        END, ', ') AS RecentQuestions,
        STRING_AGG(DISTINCT CASE 
            WHEN p.PostTypeId = 2 THEN p.Body 
            ELSE NULL 
        END, ', ') AS RecentAnswers,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) AS RankByReputation,
        RANK() OVER (ORDER BY AvgScorePerPost DESC) AS RankByAvgScore,
        DENSE_RANK() OVER (ORDER BY QuestionCount DESC) AS RankByQuestions
    FROM UserStats
),
TopUsers AS (
    SELECT UserId, DisplayName, Reputation, PostCount, QuestionCount, AnswerCount
    FROM RankedUsers
    WHERE RankByReputation <= 50
),
EngagementMetrics AS (
    SELECT 
        pu.UserId,
        pu.DisplayName,
        pu.Reputation,
        pu.PostCount,
        pu.QuestionCount,
        pu.AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT ph.Id) AS EditCount,
        AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
        MAX(CAST(p.Score AS FLOAT)) AS MaxPostScore
    FROM TopUsers pu
    LEFT JOIN Comments c ON pu.UserId = c.UserId
    LEFT JOIN Votes v ON pu.UserId = v.UserId
    LEFT JOIN Posts p ON pu.UserId = p.OwnerUserId
    LEFT JOIN PostHistory ph ON pu.UserId = ph.UserId
    GROUP BY pu.UserId, pu.DisplayName, pu.Reputation, pu.PostCount, pu.QuestionCount, pu.AnswerCount
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END AS TagType,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END AS AccessLevel,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS UsageInQuestions,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AvgScoreForTag
    FROM Tags t
    WHERE t.Count > 100
),
ComplexCalculations AS (
    SELECT 
        em.UserId,
        em.DisplayName,
        em.Reputation,
        em.PostCount,
        em.QuestionCount,
        em.AnswerCount,
        em.CommentCount,
        em.VoteCount,
        em.UpVotesReceived,
        em.DownVotesReceived,
        em.EditCount,
        em.AvgPostScore,
        em.MaxPostScore,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = em.UserId 
              AND p.CreationDate > '2020-01-01' 
              AND p.PostTypeId = 1
        ) AS RecentQuestionsCount,
        (
            SELECT STRFTIME('%Y-%m', CreationDate) 
            FROM Posts p 
            WHERE p.OwnerUserId = em.UserId 
            ORDER BY CreationDate DESC 
            LIMIT 1
        ) AS LastPostMonth,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = em.UserId 
              AND p.Score > 100
        ) AS HighScorePosts,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = em.UserId 
              AND p.ViewCount > 1000
        ) AS PopularPosts,
        (
            SELECT ROUND(
                CAST(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS FLOAT) * 100 
                / NULLIF(COUNT(v.Id), 0), 2
            ) 
            FROM Votes v 
            WHERE v.UserId = em.UserId
        ) AS UpvotePercentage,
        (
            SELECT COUNT(DISTINCT p.Id) 
            FROM Posts p 
            WHERE p.OwnerUserId = em.UserId 
              AND p.ParentId IS NULL
        ) AS OriginalPosts,
        (
            SELECT COUNT(DISTINCT p.Id) 
            FROM Posts p 
            WHERE p.OwnerUserId = em.UserId 
              AND p.ParentId IS NOT NULL
        ) AS ResponsesToOthers
    FROM EngagementMetrics em
)
SELECT 
    cc.UserId,
    cc.DisplayName,
    cc.Reputation,
    cc.PostCount,
    cc.QuestionCount,
    cc.AnswerCount,
    cc.CommentCount,
    cc.VoteCount,
    cc.UpVotesReceived,
    cc.DownVotesReceived,
    cc.EditCount,
    cc.AvgPostScore,
    cc.MaxPostScore,
    cc.RecentQuestionsCount,
    cc.LastPostMonth,
    cc.HighScorePosts,
    cc.PopularPosts,
    cc.UpvotePercentage,
    cc.OriginalPosts,
    cc.ResponsesToOthers,
    (
        SELECT COUNT(DISTINCT t.TagName)
        FROM Tags t
        WHERE t.TagName IN (
            SELECT DISTINCT TRIM(SUBSTRING(p.Tags, n.n, 
                CASE 
                    WHEN LOCATE('>', p.Tags, n.n) > 0 
                    THEN LOCATE('>', p.Tags, n.n) - n.n 
                    ELSE LENGTH(p.Tags) - n.n + 1 
                END)) 
            FROM (
                SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL 
                SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL 
                SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL 
                SELECT 10
            ) n
            WHERE n.n <= LENGTH(p.Tags)
              AND SUBSTRING(p.Tags, n.n, 1) = '<'
              AND p.OwnerUserId = cc.UserId
        )
    ) AS TagCountInPosts,
    (SELECT STRING_AGG(TagName, ', ') 
     FROM Tags t 
     WHERE t.Count > (
         SELECT AVG(Count) 
         FROM Tags
     )
     AND t.IsRequired = 1) AS PopularRequiredTags,
    (
        SELECT COUNT(DISTINCT UserId)
        FROM Votes v
        WHERE v.VoteTypeId IN (2, 3)
          AND v.PostId IN (
              SELECT Id FROM Posts p 
              WHERE p.OwnerUserId = cc.UserId
          )
    ) AS VotersWhoInteracted,
    (
        SELECT SUM(COUNT(*))
        FROM (
            SELECT p.PostTypeId, COUNT(*) as cnt
            FROM Posts p
            WHERE p.OwnerUserId = cc.UserId
            GROUP BY p.PostTypeId
        ) group_counts
    ) AS TotalPostTypesCounted,
    (
        SELECT STRING_AGG(
            CAST(p.PostTypeId AS VARCHAR) || ':' || CAST(COUNT(*) AS VARCHAR) || ';', 
            ' '
        ) 
        FROM Posts p
        WHERE p.OwnerUserId = cc.UserId
        GROUP BY p.PostTypeId
    ) AS PostTypeDistribution
FROM ComplexCalculations cc
WHERE cc.VoteCount > 0
  AND cc.PostCount > 100
  AND cc.Reputation > 10000
ORDER BY cc.Reputation DESC, cc.PostCount DESC
LIMIT 100;