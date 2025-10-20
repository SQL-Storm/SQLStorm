-- {"query": "49042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2358} 

WITH PostsActivity2019 AS (
    -- Aggregates post-related statistics for each user for posts created in 2019
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersGiven,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount_OnPosts,
        SUM(p.AnswerCount) AS TotalAnswersOnQuestionsAsked -- Only applicable for questions (PostTypeId = 1)
    FROM Posts p
    WHERE p.CreationDate >= '2019-01-01' AND p.CreationDate < '2020-01-01'
    GROUP BY p.OwnerUserId
),
AcceptedAnswersForUsersQuestions2019 AS (
    -- Counts how many answers were accepted for questions posted by each user in 2019
    SELECT
        q.OwnerUserId AS UserId,
        COUNT(q.AcceptedAnswerId) AS AcceptedAnswersReceivedCount
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Only questions
      AND q.AcceptedAnswerId IS NOT NULL
      AND q.CreationDate >= '2019-01-01' AND q.CreationDate < '2020-01-01'
    GROUP BY q.OwnerUserId
),
UsersAnswersAcceptedByOthers2019 AS (
    -- Counts how many times each user's answers were accepted by others in 2019
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(a.Id) AS AnswersAcceptedByOthersCount
    FROM Posts q  -- Question posts
    JOIN Posts a ON q.AcceptedAnswerId = a.Id AND q.PostTypeId = 1 AND a.PostTypeId = 2
    WHERE a.CreationDate >= '2019-01-01' AND a.CreationDate < '2020-01-01' -- Filter answers created in 2019
    GROUP BY a.OwnerUserId
),
UserVoteSummary2019 AS (
    -- Summarizes votes cast by each user in 2019
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast_2019,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast_2019,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCast_2019
    FROM Votes v
    WHERE v.CreationDate >= '2019-01-01' AND v.CreationDate < '2020-01-01'
    GROUP BY v.UserId
),
PostHistoryCloseVotes2019 AS (
    -- Counts modern close votes cast by users in 2019 (PostHistoryTypeId = 10)
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS ModernCloseVotesCast_2019
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.CreationDate >= '2019-01-01' AND ph.CreationDate < '2020-01-01'
    GROUP BY ph.UserId
),
UserBadgeSummary AS (
    -- Summarizes badges awarded to each user
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTagContribution2019 AS (
    -- Identifies distinct tags contributed by users through their questions in 2019
    -- Also counts posts related to specific database tags as an example
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT tag_unnest.tag) AS DistinctTagsContributed_2019,
        SUM(CASE WHEN tag_unnest.tag IN ('sql', 'database', 'postgresql', 'mysql', 'sql-server') THEN 1 ELSE 0 END) AS DatabaseRelatedPosts_2019
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag_unnest(tag)
    WHERE p.PostTypeId = 1 -- Only questions for tag contribution context
      AND p.CreationDate >= '2019-01-01' AND p.CreationDate < '2020-01-01'
      AND p.Tags IS NOT NULL
      AND length(p.Tags) > 2 -- Exclude empty or malformed tags
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.UpVotes AS UserLifetimeUpVotesReceived, -- From Users table
    u.DownVotes AS UserLifetimeDownVotesReceived, -- From Users table
    COALESCE(pa.QuestionsAsked, 0) AS QuestionsAsked_2019,
    COALESCE(pa.AnswersGiven, 0) AS AnswersGiven_2019,
    COALESCE(pa.TotalPostScore, 0) AS TotalPostScore_2019,
    COALESCE(pa.TotalViewCount, 0) AS TotalViewCount_2019,
    COALESCE(pa.TotalFavoriteCount_OnPosts, 0) AS TotalFavoriteCount_OnPosts_2019,
    COALESCE(pa.TotalAnswersOnQuestionsAsked, 0) AS TotalAnswersOnQuestionsAsked_2019,
    COALESCE(aafrq.AcceptedAnswersReceivedCount, 0) AS AcceptedAnswersForUsersQuestions_2019,
    COALESCE(uaabo.AnswersAcceptedByOthersCount, 0) AS UsersAnswersAcceptedByOthers_2019,
    COALESCE(uvs.UpVotesCast_2019, 0) AS UpVotesCast_2019,
    COALESCE(uvs.DownVotesCast_2019, 0) AS DownVotesCast_2019,
    COALESCE(uvs.FavoritesCast_2019, 0) AS FavoritesCastByUsers_2019,
    COALESCE(phcv.ModernCloseVotesCast_2019, 0) AS ModernCloseVotesCast_2019,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(utc.DistinctTagsContributed_2019, 0) AS DistinctTagsContributed_2019,
    COALESCE(utc.DatabaseRelatedPosts_2019, 0) AS DatabaseRelatedPosts_2019,
    RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(pa.TotalPostScore, 0) DESC, COALESCE(uaabo.AnswersAcceptedByOthersCount, 0) DESC) AS OverallRank_ByReputation,
    (
        COALESCE(pa.TotalPostScore, 0) * 0.5 + -- Weight post score
        COALESCE(pa.TotalFavoriteCount_OnPosts, 0) * 2 + -- Weight favorites more
        COALESCE(uaabo.AnswersAcceptedByOthersCount, 0) * 5 + -- Heavily weight accepted answers given
        COALESCE(aafrq.AcceptedAnswersReceivedCount, 0) * 3 + -- Moderately weight accepted answers received for own questions
        COALESCE(ubs.GoldBadges, 0) * 10 + -- High weight for gold badges
        COALESCE(ubs.SilverBadges, 0) * 5 + -- Medium weight for silver badges
        COALESCE(ubs.BronzeBadges, 0) * 1 + -- Low weight for bronze badges
        COALESCE(pa.QuestionsAsked, 0) * 0.1 + -- Small weight for questions asked
        COALESCE(pa.AnswersGiven, 0) * 0.2 + -- Small weight for answers given
        SQRT(COALESCE(pa.TotalViewCount, 0)) * 0.01 -- Logarithmic-like weight for views
    ) AS CalculatedInfluenceScore_2019
FROM Users u
LEFT JOIN PostsActivity2019 pa ON u.Id = pa.UserId
LEFT JOIN AcceptedAnswersForUsersQuestions2019 aafrq ON u.Id = aafrq.UserId
LEFT JOIN UsersAnswersAcceptedByOthers2019 uaabo ON u.Id = uaabo.UserId
LEFT JOIN UserVoteSummary2019 uvs ON u.Id = uvs.UserId
LEFT JOIN PostHistoryCloseVotes2019 phcv ON u.Id = phcv.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserTagContribution2019 utc ON u.Id = utc.UserId
WHERE u.Reputation > 1000 -- Filter for users with substantial reputation to focus on active contributors
  AND (COALESCE(pa.QuestionsAsked, 0) > 0 OR COALESCE(pa.AnswersGiven, 0) > 0 OR COALESCE(ubs.TotalBadges, 0) > 0) -- Ensure some activity in 2019 or lifetime badges
ORDER BY CalculatedInfluenceScore_2019 DESC, OverallRank_ByReputation
LIMIT 200;
