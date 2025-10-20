WITH TopQuestionTags AS (
    SELECT 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
        AND p.Score >= 5
),
UserTagExpertise AS (
    SELECT 
        tqt.OwnerUserId,
        tqt.TagName,
        COUNT(DISTINCT tqt.QuestionId) as QuestionsAsked,
        SUM(tqt.Score) as TotalQuestionScore,
        AVG(tqt.ViewCount) as AvgViews,
        COUNT(DISTINCT a.Id) as AnswersGiven,
        SUM(a.Score) as TotalAnswerScore,
        SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) as AcceptedAnswers
    FROM TopQuestionTags tqt
    LEFT JOIN Posts p ON tqt.QuestionId = p.Id
    LEFT JOIN Posts a ON p.Id = a.ParentId 
        AND a.PostTypeId = 2 
        AND a.OwnerUserId = tqt.OwnerUserId
    GROUP BY tqt.OwnerUserId, tqt.TagName
    HAVING COUNT(DISTINCT tqt.QuestionId) >= 3
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT v.Id) as TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvotesGiven,
        COUNT(DISTINCT c.Id) as CommentsPosted,
        COUNT(DISTINCT ph.Id) as EditsMade
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE u.Reputation >= 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagNetworkAnalysis AS (
    SELECT 
        tqt1.TagName as Tag1,
        tqt2.TagName as Tag2,
        COUNT(DISTINCT tqt1.QuestionId) as CoOccurrence,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews
    FROM TopQuestionTags tqt1
    JOIN TopQuestionTags tqt2 ON tqt1.QuestionId = tqt2.QuestionId 
        AND tqt1.TagName < tqt2.TagName
    JOIN Posts p ON tqt1.QuestionId = p.Id
    GROUP BY tqt1.TagName, tqt2.TagName
    HAVING COUNT(DISTINCT tqt1.QuestionId) >= 10
),
ExpertRanking AS (
    SELECT 
        ute.OwnerUserId,
        ute.TagName,
        ua.DisplayName,
        ua.Reputation,
        ute.QuestionsAsked,
        ute.AnswersGiven,
        ute.AcceptedAnswers,
        ute.TotalAnswerScore,
        ua.GoldBadges,
        ua.SilverBadges,
        (ute.TotalAnswerScore * 2 + ute.AcceptedAnswers * 15 + ute.QuestionsAsked * 0.5) as ExpertiseScore,
        ROW_NUMBER() OVER (PARTITION BY ute.TagName ORDER BY (ute.TotalAnswerScore * 2 + ute.AcceptedAnswers * 15 + ute.QuestionsAsked * 0.5) DESC) as TagRank
    FROM UserTagExpertise ute
    JOIN UserActivity ua ON ute.OwnerUserId = ua.UserId
    WHERE ute.AnswersGiven > 0
)
SELECT 
    er.TagName,
    er.DisplayName,
    er.Reputation,
    er.ExpertiseScore,
    er.TagRank,
    er.QuestionsAsked,
    er.AnswersGiven,
    er.AcceptedAnswers,
    er.GoldBadges,
    er.SilverBadges,
    COALESCE(tna_count.RelatedTags, 0) as RelatedTagConnections,
    COALESCE(recent_activity.RecentAnswers, 0) as AnswersLast90Days,
    COALESCE(recent_activity.RecentScore, 0) as RecentScoreLast90Days
FROM ExpertRanking er
LEFT JOIN (
    SELECT 
        Tag1 as TagName,
        COUNT(*) as RelatedTags
    FROM TagNetworkAnalysis
    WHERE CoOccurrence >= 20
    GROUP BY Tag1
    UNION ALL
    SELECT 
        Tag2 as TagName,
        COUNT(*) as RelatedTags
    FROM TagNetworkAnalysis
    WHERE CoOccurrence >= 20
    GROUP BY Tag2
) tna_count ON er.TagName = tna_count.TagName
LEFT JOIN (
    SELECT 
        a.OwnerUserId,
        tqt.TagName,
        COUNT(DISTINCT a.Id) as RecentAnswers,
        SUM(a.Score) as RecentScore
    FROM Posts a
    JOIN Posts p ON a.ParentId = p.Id
    JOIN TopQuestionTags tqt ON p.Id = tqt.QuestionId
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '90 days'
    GROUP BY a.OwnerUserId, tqt.TagName
) recent_activity ON er.OwnerUserId = recent_activity.OwnerUserId AND er.TagName = recent_activity.TagName
WHERE er.TagRank <= 10
ORDER BY er.TagName, er.TagRank
LIMIT 500;