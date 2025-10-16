-- {"query": "1408.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1964} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count, 
        1 AS Level, 
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT 
        tt.Id, 
        tt.TagName, 
        tt.Count, 
        rh.Level + 1, 
        rh.Path || tt.Id
    FROM Tags tt
    JOIN PostLinks pl ON pl.PostId = tt.ExcerptPostId AND pl.LinkTypeId = 1
    JOIN RecursiveTagHierarchy rh ON rh.Id = pl.RelatedPostId
    WHERE tt.Id <> ALL(rh.Path) AND rh.Level < 5
),
UserTopEngagers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COALESCE(SUM(vb.UpVotes),0) - COALESCE(SUM(vb.DownVotes),0) AS NetVotesGiven,
        
        (
            SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
        ) AS GoldBadgesCount,

        LEAD(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS NextReputationPlusOne,

        MAX(c.Score) AS MaxCommentScore         
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= u.CreationDate AND p.OwnerUserId IS NOT NULL
    LEFT JOIN LATERAL (
        SELECT 
            SUM(VoteCount.UpVotes) AS UpVotes,
            SUM(VoteCount.DownVotes) AS DownVotes
        FROM (
            SELECT 
                v.VoteTypeId,
                COUNT(*)::INT AS VotesCount,
                SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
            FROM Votes v
            WHERE v.UserId = u.Id
            GROUP BY v.VoteTypeId
        ) VoteCount
    ) vb ON true
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TaggedPostsAggregation AS (
    SELECT 
        p.Id AS PostId,
        windowsTag.TagName AS Tag,
        p.Score,
        p.Views,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY windowsTag.TagName ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_post_owner,

        COALESCE(ah.MaxScoreTillPost, 0) AS MaxScoreBeforeThisPost

    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) AS windowsTag(TagName)
    
    LEFT JOIN LATERAL (
        SELECT 
            MAX(pscore.Score) AS MaxScoreTillPost
        FROM Posts pscore
        WHERE pscore.CreationDate < p.CreationDate
          AND pscore.Id <> p.Id
    ) ah ON true
    
    WHERE p.PostTypeId = 1 -- Only questions for tags (only questions have tags)
),
FilteredPopularQuestions AS (
    SELECT * FROM TaggedPostsAggregation 
    WHERE Score > 5 AND MaxScoreBeforeThisPost IS NOT NULL
),
CombinedUserPosts AS (
    SELECT u.Id AS UserId, u.DisplayName, p.Id AS PostId, p.Score, p.PostTypeId, p.AcceptedAnswerId, p.Title,
           COALESCE(p.ViewCount, 0) AS ViewCount,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank
    
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 200 AND p.Score > 0
),
AggregatedAnswers AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS TopAnswerScore,
        AVG(a.Score) FILTER(WHERE a.Score > 0) AS AvgPositiveScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserCommentSentiment AS (
    SELECT UserId,
        AVG(LEN(TRIM(TEXT)) FILTER (WHERE TEXT IS NOT NULL)::FLOAT) AS AvgCommentLength,
        COUNT(*) AS CommentCount,
        COUNT(*) FILTER (WHERE LOWER(TEXT) LIKE '%thank%' OR LOWER(TEXT) LIKE '%help%') * 100.0 / NULLIF(COUNT(*), 0) AS PraiseCommentRatePerc
    FROM Comments
    GROUP BY UserId
),
UserBadgeBadges AS (
    SELECT 
        UserId,
        STRING_AGG(DISTINCT reciprocalBadge.Name || ':' || reciprocalBadge.Class::TEXT, ',') 
                            FILTER (WHERE reciprocalBadge.Class = 1) 
                            AS GoldBadgeNames,
        MIN(Date) AS FirstGoldBadgeDate
    FROM Badges
    INNER JOIN PostHistoryTypes AS postHistoryTypes ON Badges.Date >= TIMESTAMP '2008-01-01 00:00:00' -- Filter old maybe
    CROSS JOIN LATERAL (
        SELECT DISTINCT Name, Class FROM Badges 
    ) reciprocalBadge ON reciprocalBadge.UserId = Badges.UserId
    GROUP BY UserId
),
PostsWithCloseReason AS (
    SELECT
        p.Id,
        c.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate,
        ph.UserId AS ClosedByUserId
    FROM Posts p
    LEFT JOIN PostHistory ph 
        ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes c 
        ON c.Id = TRY_CAST(ph.Comment AS SMALLINT)
    WHERE p.ClosedDate IS NOT NULL OR ph.PostHistoryTypeId = 10
),
PostsWithRanksLikeAndDislike AS (
    SELECT 
        p1.Id AS PostId,
        p1.Title,
        p1.Score,
        ROW_NUMBER() OVER (PARTITION BY p1.PostTypeId ORDER BY p1.Score DESC) AS RankOfScore,
        COALESCE(q.WithPositiveScoreCount, 0) AS PositiveScoreHistoryCount,
        CASE 
            WHEN p1.Score > LAG(p1.Score) OVER (PARTITION BY p1.PostTypeId ORDER BY p1.Score) THEN TRUE
            ELSE FALSE
        END AS IsScoreTrendingUp
    FROM Posts p1
    LEFT JOIN (
        SELECT 
            ParentId, 
            COUNT(*) FILTER (WHERE Score > 0) AS WithPositiveScoreCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) q ON p1.Id = q.ParentId
    WHERE p1.PostTypeId = 1
)
SELECT
    c.BadgeOwnerId,
    ua.QuestionId,
    ua.AnswerCount,
    u.DisplayName AS UserOwner,
    ua.TopAnswerScore,
    ua.AvgPositiveScore,
    up.Reputation,
    coalesce(pbi.GoldBadgeNames, '') AS GoldBadges,
    psr.CloseReasonName AS LastClosedReason,
    utc.Level AS HintTagHierarchyDepth,
    COALESCE(com.RecentPostRank,99) AS RecentPostSequence,
    CASE WHEN fqq.Score > 50 THEN 'Popular' ELSE 'Normal' END AS PQScoreCategory,
    ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY ua.AvgPositiveScore DESC) AS RankByAvgPositiveAnswerScore,
    uc.PraiseCommentRatePerc,
    peta.Score AS PostEditTrendScore
FROM AggregatedAnswers ua
INNER JOIN Users u ON u.Id = ua.QuestionId
LEFT JOIN UserTopEngagers up ON up.Id = u.Id
LEFT JOIN UserBadgeBadges pbi ON pbi.UserId = u.Id
LEFT JOIN PostsWithCloseReason psr ON psr.Id = ua.QuestionId
LEFT JOIN RecursiveTagHierarchy utc 
    ON utc.Id = ANY (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))::int 
        FROM Posts p WHERE p.Id = ua.QuestionId
    )
LEFT JOIN CombinedUserPosts com ON com.UserId = u.Id AND com.PostId = ua.QuestionId
LEFT JOIN FilteredPopularQuestions fqq ON fqq.PostId = ua.QuestionId
LEFT JOIN UserCommentSentiment uc ON uc.UserId = u.Id
LEFT JOIN Posts peta ON peta.Id = ua.QuestionId
LEFT JOIN (
    SELECT COUNT(1) AS BadgeOwnerId
    FROM Badges
    GROUP BY UserId
    ORDER BY BadgeOwnerId DESC
    LIMIT 1
) c ON c.BadgeOwnerId = u.Id
WHERE ua.AnswerCount > 2
  AND up.Reputation > 5000
ORDER BY RankByAvgPositiveAnswerScore DESC
LIMIT 100;
