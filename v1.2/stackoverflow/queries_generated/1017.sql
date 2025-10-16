-- {"query": "1017.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1721} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.TagName] AS TagPath,
        t.Count
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        rth.TagPath || t2.TagName,
        t2.Count
    FROM Tags t2
    JOIN RecursiveTagHierarchy rth ON t2.Id <> rth.Id AND t2.Count < rth.Count AND NOT t2.TagName = ANY(rth.TagPath)
    WHERE array_length(rth.TagPath,1) < 5
),
PostCommentsAggregated AS (
    SELECT
        c.PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(LENGTH(c.Text))::FLOAT AS AvgCommentLength,
        MAX(c.CreationDate) AS LastCommentDate,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount
    FROM Comments c
    GROUP BY c.PostId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.FavoriteCount,
        pc.CommentCount,
        pc.AvgCommentLength,
        pc.LastCommentDate,
        pc.AnonymousCommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_recent_post,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS total_posts_by_user,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS total_score_by_user
    FROM Posts p
    LEFT JOIN PostCommentsAggregated pc ON p.Id = pc.PostId
    WHERE p.PostTypeId IN (1, 2)
),
EnrichedPosts AS (
    SELECT
        pa.*,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.LastBadgeDate,
        u.Reputation,
        u.CreationDate AS UserCreation,
        u.Location,
        u.DisplayName AS OwnerDisplayName,
        CASE
            WHEN pa.AcceptedAnswerId IS NOT NULL THEN (
                SELECT Score FROM Posts AS ans WHERE ans.Id = pa.AcceptedAnswerId
            )
            ELSE NULL
        END AS AcceptedAnswerScore
    FROM PostActivityWindow pa
    LEFT JOIN UserBadgeStats ub ON pa.OwnerUserId = ub.UserId
    LEFT JOIN Users u ON pa.OwnerUserId = u.Id
),
PostLinksAugmented AS (
    SELECT
        pl.Id,
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name AS LinkTypeName,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        COALESCE(p2.Score, 0) - COALESCE(p1.Score, 0) AS ScoreDifference
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts p1 ON pl.PostId = p1.Id
    LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
),
ComplexUserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(v.VoteTypeId = 2)::INT AS TotalUpVotes,
        SUM(v.VoteTypeId = 3)::INT AS TotalDownVotes,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(avg_score.avg_score, 0)::FLOAT AS AvgPostScore,
        CASE
            WHEN u.LastAccessDate < NOW() - INTERVAL '365 days' THEN 'Inactive'
            ELSE 'Active'
        END AS UserStatus,
        -- Aggregate of 3 most recent badges' names concatenated
        (SELECT STRING_AGG(Name, ', ' ORDER BY Date DESC)
         FROM Badges b2
         WHERE b2.UserId = u.Id
         LIMIT 3) AS RecentBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, AVG(Score) AS avg_score
        FROM Posts
        GROUP BY OwnerUserId
    ) avg_score ON avg_score.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, avg_score.avg_score, u.LastAccessDate
),
DuplicateQuestionDetection AS (
    SELECT
        DISTINCT p1.Id AS QuestionId,
        p1.Title AS QuestionTitle,
        p2.Id AS DuplicateOfQuestionId,
        p2.Title AS DuplicateOfTitle,
        pl.CreationDate AS LinkCreatedAt
    FROM Posts p1
    JOIN PostLinks pl ON pl.PostId = p1.Id
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE p1.PostTypeId = 1
      AND p2.PostTypeId = 1
      AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name LIKE '%Duplicate%')
      AND p1.Id <> p2.Id
      AND p1.CreationDate >= '2018-01-01' -- Limit scope for performance
),
FinalSummary AS (
    SELECT
        ep.Id AS PostId,
        ep.Title,
        ep.CreationDate,
        ep.Score,
        ep.ViewCount,
        ep.Tags,
        ep.AnswerCount,
        ep.FavoriteCount,
        ep.CommentCount,
        ep.AvgCommentLength,
        ep.AnonymousCommentCount,
        ep.GoldBadges,
        ep.SilverBadges,
        ep.BronzeBadges,
        ep.Reputation AS OwnerReputation,
        ep.OwnerDisplayName,
        ep.AcceptedAnswerScore,
        pu.UserStatus,
        dqd.DuplicateOfQuestionId,
        dqd.DuplicateOfTitle,
        pl.ScoreDifference AS LinkScoreDifference,
        CONCAT(
            COALESCE(ep.Location, 'Unknown'),
            ' | PostsByUser:', ep.total_posts_by_user,
            ' | TotalUserScore:', ep.total_score_by_user
        ) AS LocationAndUserStats,
        ROW_NUMBER() OVER (ORDER BY ep.Score DESC, ep.ViewCount DESC) AS RankByScoreView
    FROM EnrichedPosts ep
    LEFT JOIN ComplexUserEngagement pu ON pu.UserId = ep.OwnerUserId
    LEFT JOIN DuplicateQuestionDetection dqd ON dqd.QuestionId = ep.Id
    LEFT JOIN PostLinksAugmented pl ON pl.PostId = ep.Id AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked')
    WHERE ep.rn_recent_post <= 10
)
SELECT *
FROM FinalSummary
WHERE RankByScoreView <= 50
ORDER BY RankByScoreView;
