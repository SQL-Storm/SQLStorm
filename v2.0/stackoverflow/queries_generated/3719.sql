-- {"query": "3719.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2258} 

/*  Benchmark query:  heavy use of CTEs, window functions, outer joins, correlated subqueries, set operators, 
    complex predicates, string manipulation and NULL logic against the StackOverflow schema. */

WITH
-- 1. Base user data with reputation and creation info
usr AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(u.Views, 0)               AS TotalViews,
        COALESCE(u.UpVotes, 0)             AS UpVotesGiven,
        COALESCE(u.DownVotes, 0)           AS DownVotesGiven
    FROM Users u
),

-- 2. Count of badges per user, split by class and tag‑based flag
usr_badges AS (
    SELECT
        b.UserId,
        COUNT(*)                                   AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- 3. Posts (questions and answers) with tag extraction, scoring and activity metrics
usr_posts AS (
    SELECT
        p.OwnerUserId                              AS UserId,
        p.PostTypeId,
        p.Id                                       AS PostId,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        -- extract individual tags (assumes format <tag1><tag2>...)
        UNNEST(
            CASE
                WHEN p.Tags IS NOT NULL AND p.Tags <> ''
                THEN string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')
                ELSE ARRAY[]::varchar[]
            END
        )                                         AS Tag,
        -- derived columns
        CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END AS IsQuestion,
        CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END AS IsAnswer,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),

-- 4. Aggregated tag statistics per user
usr_tag_stats AS (
    SELECT
        up.UserId,
        up.Tag,
        COUNT(*)                         AS TagPostCount,
        SUM(up.Score)                    AS TagScoreSum,
        MAX(up.CreationDate)             AS TagLastUsed
    FROM usr_posts up
    GROUP BY up.UserId, up.Tag
),

-- 5. Top tag per user (by post count, tie‑break by latest use)
usr_top_tag AS (
    SELECT
        uts.UserId,
        uts.Tag,
        uts.TagPostCount,
        uts.TagScoreSum,
        ROW_NUMBER() OVER (PARTITION BY uts.UserId
                           ORDER BY uts.TagPostCount DESC, uts.TagLastUsed DESC) AS rn
    FROM usr_tag_stats uts
),
usr_best_tag AS (
    SELECT UserId, Tag, TagPostCount, TagScoreSum
    FROM usr_top_tag
    WHERE rn = 1
),

-- 6. Recent activity window (last 30 days) per user
usr_recent_activity AS (
    SELECT
        up.UserId,
        COUNT(*) FILTER (WHERE up.CreationDate >= now() - interval '30 days')          AS RecentPosts,
        COUNT(*) FILTER (WHERE up.LastActivityDate >= now() - interval '30 days')    AS RecentEdits,
        SUM(up.Score) FILTER (WHERE up.CreationDate >= now() - interval '30 days')   AS RecentScore
    FROM usr_posts up
    GROUP BY up.UserId
),

-- 7. Correlated subquery to fetch the most recent vote type per user
usr_last_vote AS (
    SELECT
        v.UserId,
        v.VoteTypeId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.UserId IS NOT NULL
),
usr_latest_vote AS (
    SELECT UserId, VoteTypeId, CreationDate
    FROM usr_last_vote
    WHERE rn = 1
),

-- 8. Combine everything with left outer joins and compute final metrics
final_user_metrics AS (
    SELECT
        u.Id                                          AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ub.BadgeCount, 0)                    AS TotalBadges,
        COALESCE(ub.GoldBadges, 0)                    AS GoldBadges,
        COALESCE(ub.SilverBadges, 0)                  AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0)                  AS BronzeBadges,
        COALESCE(ub.TagBasedBadges, 0)                AS TagBasedBadges,
        COALESCE(p.PostCount, 0)                      AS TotalPosts,
        COALESCE(p.QuestionCount, 0)                  AS QuestionCount,
        COALESCE(p.AnswerCount, 0)                    AS AnswerCount,
        COALESCE(p.TotalScore, 0)                     AS AggregateScore,
        COALESCE(p.AvgScore, 0)                       AS AvgPostScore,
        COALESCE(t.Tag, '(none)')                     AS TopTag,
        COALESCE(t.TagPostCount, 0)                   AS TopTagPostCount,
        COALESCE(t.TagScoreSum, 0)                    AS TopTagScoreSum,
        COALESCE(r.RecentPosts, 0)                    AS PostsLast30Days,
        COALESCE(r.RecentEdits, 0)                    AS EditsLast30Days,
        COALESCE(r.RecentScore, 0)                    AS ScoreLast30Days,
        lv.VoteTypeId                                AS LastVoteTypeId,
        lv.CreationDate                              AS LastVoteDate,
        -- derived ranking fields
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)               AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation
                           ORDER BY u.CreationDate ASC)            AS RepTieBreakRank
    FROM usr u
    LEFT JOIN (
        SELECT
            up.OwnerUserId                              AS UserId,
            COUNT(*)                                    AS PostCount,
            SUM(CASE WHEN up.PostTypeId = 1 THEN 1 ELSE 0 END)   AS QuestionCount,
            SUM(CASE WHEN up.PostTypeId = 2 THEN 1 ELSE 0 END)   AS AnswerCount,
            SUM(up.Score)                              AS TotalScore,
            AVG(up.Score)                              AS AvgScore
        FROM Posts up
        GROUP BY up.OwnerUserId
    ) p ON p.UserId = u.Id
    LEFT JOIN usr_badges ub ON ub.UserId = u.Id
    LEFT JOIN usr_best_tag t ON t.UserId = u.Id
    LEFT JOIN usr_recent_activity r ON r.UserId = u.Id
    LEFT JOIN usr_latest_vote lv ON lv.UserId = u.Id
),

-- 9. Create a unioned result set that also returns an aggregated "site summary" row
site_summary AS (
    SELECT
        0                         AS UserId,
        'Site Summary'            AS DisplayName,
        SUM(u.Reputation)         AS Reputation,
        MIN(u.CreationDate)       AS FirstUserDate,
        MAX(u.LastAccessDate)     AS LastActiveUserDate,
        SUM(ub.BadgeCount)        AS TotalBadges,
        SUM(p.PostCount)          AS TotalPosts,
        SUM(p.QuestionCount)      AS TotalQuestions,
        SUM(p.AnswerCount)        AS TotalAnswers,
        SUM(p.TotalScore)         AS TotalScore,
        AVG(p.AvgScore)           AS AvgScorePerPost,
        NULL                      AS TopTag,
        NULL                      AS TopTagPostCount,
        NULL                      AS TopTagScoreSum,
        NULL                      AS PostsLast30Days,
        NULL                      AS EditsLast30Days,
        NULL                      AS ScoreLast30Days,
        NULL                      AS LastVoteTypeId,
        NULL                      AS LastVoteDate,
        NULL                      AS ReputationRank,
        NULL                      AS RepTieBreakRank
    FROM Users u
    LEFT JOIN usr_badges ub ON ub.UserId = u.Id
    LEFT JOIN (
        SELECT
            OwnerUserId          AS UserId,
            COUNT(*)            AS PostCount,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
            SUM(Score)          AS TotalScore,
            AVG(Score)          AS AvgScore
        FROM Posts
        GROUP BY OwnerUserId
    ) p ON p.UserId = u.Id
)

SELECT *
FROM final_user_metrics
WHERE ReputationRank <= 100                                   -- top‑100 users
UNION ALL
SELECT *
FROM site_summary;
