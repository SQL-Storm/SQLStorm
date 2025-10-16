-- {"query": "536.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2471} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS AncestorTags
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        rh.Level + 1,
        rh.AncestorTags || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy rh ON child.Id > rh.Id
    WHERE child.IsModeratorOnly = 0 AND child.IsRequired = 0
    AND NOT child.TagName = ANY(rh.AncestorTags)
    AND rh.Level < 3
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostScoreRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserTopPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
AcceptedAnswersWithVotes AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.ViewCount AS AnswerViewCount,
        a.OwnerUserId AS AnswerOwnerUserId,
        v.UpVotes,
        v.DownVotes,
        v.Reputation,
        v.DisplayName AS AnswerOwnerName
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.UpVotes,
            u.DownVotes
        FROM Users u
    ) v ON a.OwnerUserId = v.Id
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),
PostCommentsAggregated AS (
    SELECT
        c.PostId,
        COUNT(*) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
),
PostHistoryCloseReasonCounts AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^\d+$'
    GROUP BY ph.PostId, crt.Name
),
QuestionsWithCloseInfo AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        pcac.CloseReason,
        pcac.CloseVotesCount,
        phc.LastCloseDate
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            MAX(CreationDate) AS LastCloseDate
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        GROUP BY PostId
    ) phc ON phc.PostId = p.Id
    LEFT JOIN PostHistoryCloseReasonCounts pcac ON pcac.PostId = p.Id
    WHERE p.PostTypeId = 1
),
TopUsersByBadgeRatio AS (
    SELECT
        ubc.UserId,
        ubc.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        u.Reputation,
        u.CreationDate,
        u.Views,
        CASE WHEN ubc.BronzeBadges = 0 THEN NULL ELSE ubc.GoldBadges::FLOAT / ubc.BronzeBadges END AS GoldToBronzeRatio,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM UserBadgeCounts ubc
    JOIN Users u ON u.Id = ubc.UserId
    WHERE u.Reputation > 1000
),
PostsWithComplexTagParsing AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) AS SingleTag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagPopularity AS (
    SELECT
        tag.SingleTag,
        COUNT(*) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViewCount,
        MIN(p.CreationDate) AS FirstUsed,
        MAX(p.CreationDate) AS LastUsed
    FROM PostsWithComplexTagParsing tag
    JOIN Posts p ON p.Id = tag.Id
    GROUP BY tag.SingleTag
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
UserActivityRanked AS (
    SELECT
        uas.*,
        RANK() OVER (ORDER BY QuestionsPosted DESC, AnswersPosted DESC, CommentsMade DESC) AS ActivityRank
    FROM UserActivitySummary uas
),
CombinedResults AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        pc.TotalComments,
        pc.AvgCommentScore,
        pc.LastCommentDate,
        qci.CloseReason,
        qci.CloseVotesCount,
        qci.LastCloseDate,
        ts.SingleTag,
        tp.QuestionCount,
        tp.AvgScore AS TagAvgScore,
        tp.MaxViewCount AS TagMaxViewCount,
        tp.FirstUsed AS TagFirstUsed,
        tp.LastUsed AS TagLastUsed,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.ActivityRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = p.OwnerUserId
    LEFT JOIN PostCommentsAggregated pc ON pc.PostId = p.Id
    LEFT JOIN QuestionsWithCloseInfo qci ON qci.QuestionId = p.Id AND p.PostTypeId = 1
    LEFT JOIN PostsWithComplexTagParsing ts ON ts.Id = p.Id
    LEFT JOIN TagPopularity tp ON tp.SingleTag = ts.SingleTag
    LEFT JOIN UserActivityRanked ua ON ua.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1
)
SELECT
    cr.PostId,
    cr.Title,
    cr.Score,
    cr.ViewCount,
    cr.CreationDate,
    cr.OwnerUserId,
    cr.OwnerName,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.TotalComments,
    cr.AvgCommentScore,
    cr.LastCommentDate,
    cr.CloseReason,
    cr.CloseVotesCount,
    cr.LastCloseDate,
    cr.SingleTag,
    cr.QuestionCount,
    cr.TagAvgScore,
    cr.TagMaxViewCount,
    cr.TagFirstUsed,
    cr.TagLastUsed,
    cr.QuestionsPosted,
    cr.AnswersPosted,
    cr.CommentsMade,
    cr.UpVotesGiven,
    cr.DownVotesGiven,
    cr.LastPostDate,
    cr.LastCommentDate,
    cr.ActivityRank,
    -- Complex expression combining score and badges weighted
    (cr.Score * 0.7 + COALESCE(cr.GoldBadges,0) * 5 + COALESCE(cr.SilverBadges,0) * 2 + COALESCE(cr.BronzeBadges,0) * 1.5) /
    NULLIF(cr.ViewCount, 0) AS ScorePerViewRatio,
    -- String manipulation: truncated title with badge summary
    LEFT(cr.Title, 50) || '...' || ' [' ||
    COALESCE(cr.GoldBadges::TEXT, '0') || 'G/' ||
    COALESCE(cr.SilverBadges::TEXT, '0') || 'S/' ||
    COALESCE(cr.BronzeBadges::TEXT, '0') || 'B]' AS TitleBadgeSummary,
    -- Window function: rank of post by score within tag
    RANK() OVER (PARTITION BY cr.SingleTag ORDER BY cr.Score DESC NULLS LAST) AS TagScoreRank,
    -- Correlated subquery: count of answers by the owner user in last 30 days
    (
        SELECT COUNT(*)
        FROM Posts p2
        WHERE p2.OwnerUserId = cr.OwnerUserId
          AND p2.PostTypeId = 2
          AND p2.CreationDate >= NOW() - INTERVAL '30 days'
    ) AS RecentAnswersByOwner,
    -- NULL logic: check if post is closed and if close reason is known
    CASE
        WHEN cr.CloseVotesCount > 0 AND cr.CloseReason IS NOT NULL THEN 'Closed: ' || cr.CloseReason
        WHEN cr.CloseVotesCount > 0 THEN 'Closed: Unknown Reason'
        ELSE 'Open'
    END AS PostStatus
FROM CombinedResults cr
WHERE cr.Score > 5
  AND (cr.CloseVotesCount IS NULL OR cr.CloseVotesCount < 3)
  AND cr.ActivityRank <= 100
ORDER BY cr.ScorePerViewRatio DESC NULLS LAST, cr.CreationDate DESC
LIMIT 100;
