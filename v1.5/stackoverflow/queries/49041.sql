WITH PopularTags AS (
    SELECT
        q_tag AS TagName,
        COUNT(DISTINCT p.Id) AS TaggedQuestionCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT TRIM(value) AS q_tag
        FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS value
    ) AS t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '3' YEAR)
      AND p.ViewCount > 1000
      AND p.Score > 50
    GROUP BY q_tag
    ORDER BY TaggedQuestionCount DESC
    LIMIT 20
),
HighImpactQuestions AS (
    SELECT DISTINCT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        p.AcceptedAnswerId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        p.FavoriteCount AS QuestionFavoriteCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT DISTINCT TRIM(value) AS q_tag
        FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS value
    ) AS t
    JOIN PopularTags pt ON t.q_tag = pt.TagName
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '3' YEAR)
      AND p.ViewCount > 5000
      AND p.Score > 100
      AND p.AnswerCount >= 5
      AND p.FavoriteCount >= 10
),
HighImpactPosts AS (
    SELECT QuestionId AS PostId FROM HighImpactQuestions
    UNION ALL
    SELECT p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.ParentId IN (SELECT QuestionId FROM HighImpactQuestions)
),
UserContributionsSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        u.Views AS UserProfileViews,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT hiq_q.QuestionId) AS QuestionsInHighImpactTagsOwned,
        COUNT(DISTINCT p_a.Id) AS AnswersToHighImpactQuestions,
        COALESCE(SUM(p_a.Score), 0) AS ScoreOnAnswersToHighImpactQuestions,
        COUNT(DISTINCT c.Id) AS CommentsOnHighImpactPosts,
        COALESCE(SUM(c.Score), 0) AS ScoreOfCommentsOnHighImpactPosts,
        COUNT(DISTINCT ph.Id) AS EditsOnHighImpactPosts,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpvotesGivenToHighImpactPosts,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS DownvotesGivenToHighImpactPosts
    FROM Users u
    LEFT JOIN HighImpactQuestions hiq_q ON u.Id = hiq_q.QuestionOwnerId
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2 AND p_a.ParentId IN (SELECT QuestionId FROM HighImpactQuestions)
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId IN (SELECT PostId FROM HighImpactPosts)
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostId IN (SELECT PostId FROM HighImpactPosts)
                               AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.PostId IN (SELECT PostId FROM HighImpactPosts)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, u.LastAccessDate
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserTotalUpVotes,
    ucs.UserTotalDownVotes,
    ucs.LastAccessDate,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    ucs.QuestionsInHighImpactTagsOwned,
    ucs.AnswersToHighImpactQuestions,
    ucs.ScoreOnAnswersToHighImpactQuestions,
    ucs.CommentsOnHighImpactPosts,
    ucs.ScoreOfCommentsOnHighImpactPosts,
    ucs.EditsOnHighImpactPosts,
    ucs.UpvotesGivenToHighImpactPosts,
    ucs.DownvotesGivenToHighImpactPosts,
    ( -- InfluenceScore
        (ucs.Reputation * 0.001)
        + ((ucs.UserTotalUpVotes - ucs.UserTotalDownVotes) * 0.005)
        + (ucs.AnswersToHighImpactQuestions * 10)
        + (ucs.ScoreOnAnswersToHighImpactQuestions * 0.1)
        + (ucs.CommentsOnHighImpactPosts * 2)
        + (ucs.ScoreOfCommentsOnHighImpactPosts * 0.05)
        + (ucs.EditsOnHighImpactPosts * 3)
        + (COALESCE(ubs.GoldBadges, 0) * 20 + COALESCE(ubs.SilverBadges, 0) * 10 + COALESCE(ubs.BronzeBadges, 0) * 2)
        + (ucs.UpvotesGivenToHighImpactPosts * 0.5)
        - (ucs.DownvotesGivenToHighImpactPosts * 0.2)
        + (CASE
            WHEN ucs.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' MONTH) THEN 50
            WHEN ucs.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '6' MONTH) THEN 20
            WHEN ucs.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR) THEN 10
            ELSE 0
          END)
    ) AS InfluenceScore,
    RANK() OVER (ORDER BY (
        (ucs.Reputation * 0.001)
        + ((ucs.UserTotalUpVotes - ucs.UserTotalDownVotes) * 0.005)
        + (ucs.AnswersToHighImpactQuestions * 10)
        + (ucs.ScoreOnAnswersToHighImpactQuestions * 0.1)
        + (ucs.CommentsOnHighImpactPosts * 2)
        + (ucs.ScoreOfCommentsOnHighImpactPosts * 0.05)
        + (ucs.EditsOnHighImpactPosts * 3)
        + (COALESCE(ubs.GoldBadges, 0) * 20 + COALESCE(ubs.SilverBadges, 0) * 10 + COALESCE(ubs.BronzeBadges, 0) * 2)
        + (ucs.UpvotesGivenToHighImpactPosts * 0.5)
        - (ucs.DownvotesGivenToHighImpactPosts * 0.2)
        + (CASE
            WHEN ucs.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' MONTH) THEN 50
            WHEN ucs.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '6' MONTH) THEN 20
            WHEN ucs.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR) THEN 10
            ELSE 0
          END)
    ) DESC, ucs.Reputation DESC, ucs.LastAccessDate DESC
    ) AS GlobalInfluenceRank
FROM UserContributionsSummary ucs
LEFT JOIN UserBadgeSummary ubs ON ucs.UserId = ubs.UserId
WHERE ucs.Reputation > 750
  AND (ucs.AnswersToHighImpactQuestions > 0 OR ucs.EditsOnHighImpactPosts > 0 OR ucs.CommentsOnHighImpactPosts > 0 OR ucs.QuestionsInHighImpactTagsOwned > 0)
ORDER BY InfluenceScore DESC, ucs.Reputation DESC, ucs.LastAccessDate DESC
LIMIT 200;