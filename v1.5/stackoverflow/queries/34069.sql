-- {"query": "34069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1095} 
WITH UserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        AVG(p.Score) AS AvgPostScore,
        COUNT(p.Id) AS TotalPosts,
        MAX(p.Score) AS MaxPostScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT
        pt.OwnerUserId AS UserId,
        UNNEST(string_to_array(SUBSTRING(pt.Tags, 2, LENGTH(pt.Tags) - 2), '><')) AS TagName,
        COUNT(*) AS TagCount
    FROM Posts pt
    WHERE pt.PostTypeId = 1 AND pt.OwnerUserId IS NOT NULL
    GROUP BY pt.OwnerUserId, TagName
),
TopUserTags AS (
    SELECT
        UserId,
        TagName,
        TagCount,
        RANK() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS TagRank
    FROM TopTags
),
UserTopTags AS (
    SELECT UserId, STRING_AGG(TagName, ', ') AS TopTagsList
    FROM TopUserTags
    WHERE TagRank <= 3
    GROUP BY UserId
),
QuestionActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS QuestionsAsked,
        AVG(p.ViewCount) AS AvgQuestionViews,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TimesClosed,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TimesReopened
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11)
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
AnswerActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS AnswersGiven,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(DISTINCT p.ParentId) AS QuestionsAnsweredCount
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
VoteSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesGiven,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoritesGiven
    FROM Votes v
    INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    ub.UserId,
    ub.DisplayName,
    ub.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.AvgPostScore,
    ub.TotalPosts,
    ub.MaxPostScore,
    COALESCE(ut.TopTagsList, '') AS TopTags,
    COALESCE(qa.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(qa.AvgQuestionViews, 0) AS AvgQuestionViews,
    COALESCE(qa.TimesClosed, 0) AS TimesClosed,
    COALESCE(qa.TimesReopened, 0) AS TimesReopened,
    COALESCE(aa.AnswersGiven, 0) AS AnswersGiven,
    COALESCE(aa.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(aa.QuestionsAnsweredCount, 0) AS QuestionsAnsweredCount,
    COALESCE(vs.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(vs.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(vs.FavoritesGiven, 0) AS FavoritesGiven
FROM
    (SELECT u.Id as UserId, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.AvgPostScore, ub.TotalPosts, ub.MaxPostScore
     FROM Users u
     LEFT JOIN UserBadges ub ON u.Id = ub.UserId
     WHERE u.Reputation > 1000
    ) ub
LEFT JOIN UserTopTags ut ON ut.UserId = ub.UserId
LEFT JOIN QuestionActivity qa ON qa.UserId = ub.UserId
LEFT JOIN AnswerActivity aa ON aa.UserId = ub.UserId
LEFT JOIN VoteSummary vs ON vs.UserId = ub.UserId
ORDER BY ub.Reputation DESC
LIMIT 100;