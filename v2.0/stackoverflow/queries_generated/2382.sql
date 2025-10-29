-- {"query": "2382.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1714} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS AncestorTags
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        c.Count,
        r.AncestorTags || c.TagName
    FROM Tags c
    JOIN RecursiveTagHierarchy r ON c.Id <> r.Id AND array_length(r.AncestorTags,1) < 3
    WHERE c.IsRequired = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(COALESCE(vVotes.UpVotes,0)) AS TotalUpVotes,
        SUM(COALESCE(vVotes.DownVotes,0)) AS TotalDownVotes,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > u.CreationDate
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) vVotes ON vVotes.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
),
CloseVotesCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVotes,
        MAX(CASE WHEN crt.Name IS NOT NULL THEN crt.Name ELSE 'Unknown' END) AS LastCloseReason
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment::INT = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.CreationDate > NOW() - INTERVAL '1 month'
    GROUP BY ph.PostId
),
BadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserScoreStats AS (
    SELECT
        u.Id,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        STDDEV(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS StdDevPostScore,
        COUNT(p.Id) AS TotalPosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
FinalReport AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        us.AvgPostScore,
        us.StdDevPostScore,
        us.TotalPosts,
        ua.ReputationRank,
        tp.Title AS TopQuestionTitle,
        tp.Score AS TopQuestionScore,
        cv.CloseVotes,
        cv.ReopenVotes,
        cv.LastCloseReason,
        STRING_AGG(DISTINCT unnest(string_to_array(tp.Tags, '><'))), ', ') AS TagsOnTopQuestion
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON bs.UserId = ua.UserId
    LEFT JOIN UserScoreStats us ON us.Id = ua.UserId
    LEFT JOIN TopPosts tp ON tp.OwnerUserId = ua.UserId AND tp.PostTypeId = 1 AND tp.ScoreRank = 1
    LEFT JOIN CloseVotesCounts cv ON cv.PostId = tp.Id
    GROUP BY
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        us.AvgPostScore,
        us.StdDevPostScore,
        us.TotalPosts,
        ua.ReputationRank,
        tp.Title,
        tp.Score,
        cv.CloseVotes,
        cv.ReopenVotes,
        cv.LastCloseReason
)
SELECT
    fr.UserId,
    fr.DisplayName,
    fr.ReputationRank,
    fr.QuestionsAsked,
    fr.AnswersGiven,
    fr.CommentsMade,
    fr.TotalUpVotes,
    fr.TotalDownVotes,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    COALESCE(fr.AvgPostScore, 0)::NUMERIC(10,2) AS AvgPostScore,
    COALESCE(fr.StdDevPostScore, 0)::NUMERIC(10,2) AS StdDevPostScore,
    fr.TotalPosts,
    fr.TopQuestionTitle,
    fr.TopQuestionScore,
    fr.CloseVotes,
    fr.ReopenVotes,
    fr.LastCloseReason,
    fr.TagsOnTopQuestion,
    -- Complex conditional expression with NULL logic and string functions
    CASE
        WHEN fr.TopQuestionScore IS NULL THEN 'No top question score'
        WHEN fr.TopQuestionScore < 0 THEN concat('Negative score: ', fr.TopQuestionScore)
        WHEN fr.CloseVotes > fr.ReopenVotes THEN concat('Closed: Reason - ', coalesce(fr.LastCloseReason, 'Unknown'))
        ELSE 'Open and active'
    END AS PostStatus
FROM FinalReport fr
WHERE fr.TotalPosts > 20
  AND fr.ReputationRank <= 100
ORDER BY fr.ReputationRank
LIMIT 50

UNION

SELECT
    u.Id AS UserId,
    u.DisplayName,
    NULL::int AS ReputationRank,
    0 AS QuestionsAsked,
    0 AS AnswersGiven,
    0 AS CommentsMade,
    0 AS TotalUpVotes,
    0 AS TotalDownVotes,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0.0 AS AvgPostScore,
    0.0 AS StdDevPostScore,
    0 AS TotalPosts,
    NULL::varchar AS TopQuestionTitle,
    NULL::int AS TopQuestionScore,
    0 AS CloseVotes,
    0 AS ReopenVotes,
    NULL::varchar AS LastCloseReason,
    NULL::varchar AS TagsOnTopQuestion,
    'Inactive user' AS PostStatus
FROM Users u
WHERE NOT EXISTS (
    SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id
)
AND u.Reputation > 10000
ORDER BY u.DisplayName
LIMIT 10;
