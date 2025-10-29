-- {"query": "7797.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2985}
WITH RECURSIVE PostHierarchy AS (
    SELECT 
        p.Id AS PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        0 AS Level,
        CAST(p.Id AS VARCHAR(1000)) AS Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    UNION ALL
    SELECT 
        p.Id AS PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ph.Level + 1,
        ph.Path || '->' || CAST(p.Id AS VARCHAR(1000)) AS Path
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.PostId
    WHERE ph.Level < 10
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgPostScore,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        STRING_AGG(CAST(c.Id AS VARCHAR), ', ') AS CommentIds,
        STRING_AGG(c.Text, ' | ') AS CommentTexts,
        MIN(c.CreationDate) AS FirstCommentDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountByVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NetVotes,
        MAX(v.CreationDate) AS LastVoteDate,
        p.Tags
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 5)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.CreationDate, p.OwnerUserId, p.AcceptedAnswerId, p.Tags
),
AnswerStats AS (
    SELECT 
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveEditDate,
        p.LastActivityDate,
        COALESCE(p.OwnerDisplayName, 'Anonymous') AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 2
    GROUP BY p.Id, p.ParentId, p.Score, p.CreationDate, p.OwnerUserId, p.LastEditDate, p.LastActivityDate, p.OwnerDisplayName
),
CombinedStats AS (
    SELECT 
        qs.QuestionId,
        qs.Title,
        qs.Score AS QuestionScore,
        qs.ViewCount AS QuestionViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.FavoriteCount,
        qs.CreationDate AS QuestionCreationDate,
        qs.OwnerUserId,
        qs.AcceptedAnswerId,
        qs.CommentIds,
        qs.CommentTexts,
        qs.FirstCommentDate,
        qs.LastCommentDate,
        qs.VoteCount AS QuestionVoteCount,
        qs.UpVotes AS QuestionUpVotes,
        qs.DownVotes AS QuestionDownVotes,
        qs.FavoriteCountByVotes AS QuestionFavoriteCount,
        qs.NetVotes AS QuestionNetVotes,
        qs.LastVoteDate AS QuestionLastVoteDate,
        qs.Tags,
        COALESCE(array_length(string_to_array(qs.Tags, '><'), 1) - 1, 0) AS TagCount,
        STRING_AGG(DISTINCT TRIM(SUBSTRING(qs.Tags FROM 2 FOR CHAR_LENGTH(qs.Tags) - 2)), ', ') AS TagList,
        COALESCE(as1.AnswerId, 0) AS TopAnswerId,
        COALESCE(as1.Score, 0) AS TopAnswerScore,
        COALESCE(as1.OwnerUserId, 0) AS TopAnswerOwnerId,
        COALESCE(as1.CreationDate, TIMESTAMP '1900-01-01') AS TopAnswerCreationDate,
        COALESCE(as1.RankByScore, 0) AS TopAnswerRank,
        COALESCE(as1.VoteCount, 0) AS TopAnswerVoteCount,
        COALESCE(as1.UpVotes, 0) AS TopAnswerUpVotes,
        COALESCE(as1.DownVotes, 0) AS TopAnswerDownVotes,
        COALESCE(as1.LastVoteDate, TIMESTAMP '1900-01-01') AS TopAnswerLastVoteDate
    FROM QuestionStats qs
    LEFT JOIN AnswerStats as1 ON qs.QuestionId = as1.QuestionId AND as1.RankByScore = 1
    GROUP BY 
        qs.QuestionId, qs.Title, qs.Score, qs.ViewCount, qs.AnswerCount, qs.CommentCount, qs.FavoriteCount, 
        qs.CreationDate, qs.OwnerUserId, qs.AcceptedAnswerId, qs.CommentIds, qs.CommentTexts, qs.FirstCommentDate, 
        qs.LastCommentDate, qs.VoteCount, qs.UpVotes, qs.DownVotes, qs.FavoriteCountByVotes, qs.NetVotes, 
        qs.LastVoteDate, qs.Tags, as1.AnswerId, as1.Score, as1.OwnerUserId, as1.CreationDate, as1.RankByScore, 
        as1.VoteCount, as1.UpVotes, as1.DownVotes, as1.LastVoteDate
)
SELECT 
    cs.QuestionId,
    cs.Title,
    cs.QuestionScore,
    cs.QuestionViewCount,
    cs.AnswerCount,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.QuestionCreationDate,
    cs.OwnerUserId,
    cs.AcceptedAnswerId,
    COALESCE(cs.CommentIds, '') AS CommentIds,
    COALESCE(cs.CommentTexts, '') AS CommentTexts,
    cs.FirstCommentDate,
    cs.LastCommentDate,
    cs.QuestionVoteCount,
    cs.QuestionUpVotes,
    cs.QuestionDownVotes,
    cs.QuestionFavoriteCount,
    cs.QuestionNetVotes,
    cs.QuestionLastVoteDate,
    COALESCE(cs.Tags, '') AS Tags,
    COALESCE(cs.TagCount, 0) AS TagCount,
    COALESCE(cs.TagList, '') AS TagList,
    cs.TopAnswerId,
    cs.TopAnswerScore,
    cs.TopAnswerOwnerId,
    cs.TopAnswerCreationDate,
    cs.TopAnswerRank,
    cs.TopAnswerVoteCount,
    cs.TopAnswerUpVotes,
    cs.TopAnswerDownVotes,
    cs.TopAnswerLastVoteDate,
    COALESCE(us.DisplayName, 'Unknown') AS OwnerDisplayName,
    COALESCE(us.Reputation, 0) AS OwnerReputation,
    COALESCE(us.BadgeCount, 0) AS OwnerBadgeCount,
    COALESCE(us.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(us.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(us.BronzeBadges, 0) AS OwnerBronzeBadges,
    COALESCE(us.BadgeNames, '') AS OwnerBadgeNames,
    COALESCE(us.AvgPostScore, 0) AS OwnerAvgPostScore,
    COALESCE(us.TotalPosts, 0) AS OwnerTotalPosts,
    COALESCE(us.Questions, 0) AS OwnerQuestions,
    COALESCE(us.Answers, 0) AS OwnerAnswers,
    CASE 
        WHEN cs.QuestionNetVotes > 10 AND cs.QuestionScore > 0 THEN 'Highly Engaged'
        WHEN cs.QuestionNetVotes > 5 AND cs.QuestionScore >= 0 THEN 'Engaged'
        WHEN cs.QuestionNetVotes > 0 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    CASE 
        WHEN cs.AnswerCount > 5 THEN 'Well Answered'
        WHEN cs.AnswerCount > 2 THEN 'Some Answers'
        WHEN cs.AnswerCount = 0 THEN 'No Answers Yet'
        ELSE 'Minimal Answers'
    END AS AnswerStatus,
    AGE(TIMESTAMP '2024-10-01 12:34:56', cs.QuestionCreationDate) AS TimeSinceCreation,
    CASE 
        WHEN cs.QuestionNetVotes > 0 AND cs.QuestionScore > 0 THEN 'Positive Score'
        WHEN cs.QuestionNetVotes < 0 AND cs.QuestionScore < 0 THEN 'Negative Score'
        ELSE 'Neutral Score'
    END AS ScoreStatus,
    CASE 
        WHEN cs.AnswerCount > 0 AND cs.AcceptedAnswerId > 0 THEN 'Answered & Accepted'
        WHEN cs.AnswerCount > 0 THEN 'Answered but Not Accepted'
        ELSE 'Unanswered'
    END AS AnswerStatusDetailed,
    CASE 
        WHEN cs.QuestionNetVotes > 20 THEN 'Viral Question'
        WHEN cs.QuestionNetVotes > 10 THEN 'Popular Question'
        WHEN cs.QuestionNetVotes > 5 THEN 'Interesting Question'
        WHEN cs.QuestionNetVotes > 0 THEN 'Minor Question'
        ELSE 'Unpopular Question'
    END AS PopularityLevel,
    COALESCE(ph.Path, 'No Hierarchy') AS PostHierarchyPath,
    COALESCE(array_length(string_to_array(COALESCE(cs.TagList, ''), ', '), 1), 0) AS DistinctTagCount,
    STRING_AGG(DISTINCT TRIM(SUBSTRING(cs.TagList FROM POSITION(',' IN cs.TagList) + 1)), ', ') AS AdditionalTags
FROM CombinedStats cs
LEFT JOIN UserStats us ON cs.OwnerUserId = us.UserId
LEFT JOIN PostHierarchy ph ON cs.QuestionId = ph.PostId
WHERE cs.QuestionId IS NOT NULL
    AND (cs.QuestionCreationDate >= DATE '2020-01-01' OR cs.QuestionCreationDate IS NULL)
    AND cs.QuestionScore IS NOT NULL
    AND cs.QuestionScore >= -100
    AND cs.Tags IS NOT NULL
GROUP BY 
    cs.QuestionId, cs.Title, cs.QuestionScore, cs.QuestionViewCount, cs.AnswerCount, cs.CommentCount, 
    cs.FavoriteCount, cs.QuestionCreationDate, cs.OwnerUserId, cs.AcceptedAnswerId, cs.CommentIds, 
    cs.CommentTexts, cs.FirstCommentDate, cs.LastCommentDate, cs.QuestionVoteCount, cs.QuestionUpVotes, 
    cs.QuestionDownVotes, cs.QuestionFavoriteCount, cs.QuestionNetVotes, cs.QuestionLastVoteDate, 
    cs.Tags, cs.TagCount, cs.TagList, cs.TopAnswerId, cs.TopAnswerScore, cs.TopAnswerOwnerId, 
    cs.TopAnswerCreationDate, cs.TopAnswerRank, cs.TopAnswerVoteCount, cs.TopAnswerUpVotes, 
    cs.TopAnswerDownVotes, cs.TopAnswerLastVoteDate, us.DisplayName, us.Reputation, us.BadgeCount, 
    us.GoldBadges, us.SilverBadges, us.BronzeBadges, us.BadgeNames, us.AvgPostScore, us.TotalPosts, 
    us.Questions, us.Answers, ph.Path
HAVING 
    COUNT(*) > 0
    AND (COALESCE(cs.QuestionNetVotes, 0) > 0 OR COALESCE(cs.QuestionScore, 0) > 0)
    AND (COALESCE(cs.AnswerCount, 0) >= 0)
    AND (COALESCE(cs.CommentCount, 0) >= 0)
ORDER BY 
    cs.QuestionNetVotes DESC, 
    cs.QuestionScore DESC, 
    cs.QuestionViewCount DESC, 
    cs.QuestionCreationDate DESC
LIMIT 1000;