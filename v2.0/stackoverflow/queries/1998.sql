-- {"query": "1998.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2470}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        (COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id)) AS OverallActivityScore,
        SUM(CASE WHEN p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 1 ELSE 0 END) AS PostsLastYear,
        SUM(CASE WHEN c.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 1 ELSE 0 END) AS CommentsLastYear,
        (SUM(CASE WHEN p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 1 ELSE 0 END) +
         SUM(CASE WHEN c.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 1 ELSE 0 END)) AS ActivityLastYearScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
    HAVING (COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id)) > 0
),
AnswerPerformance AS (
    SELECT
        p.OwnerUserId AS UserId,
        COALESCE(AVG(CAST(p.Score AS NUMERIC)), 0) AS AverageAnswerScore,
        COALESCE(AVG(CAST(LENGTH(p.Body) AS NUMERIC)), 0) AS AverageAnswerBodyLength,
        COUNT(p.Id) AS AnswersCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
UserTagDiversity AS (
    -- Expand tags using a lateral split to avoid SRF inside aggregates
    SELECT
        q.OwnerUserId AS UserId,
        COUNT(DISTINCT TRIM(tag)) AS DistinctQuestionTagsCount
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><')) AS tag
    ) t
    WHERE q.PostTypeId = 1
      AND q.Tags IS NOT NULL
      AND LENGTH(q.Tags) > 2
    GROUP BY q.OwnerUserId
),
UserFavoriteReceipts AS (
    SELECT
        p.OwnerUserId AS UserId,
        MAX(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS HasReceivedFavoriteVote
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE v.VoteTypeId = 5
    GROUP BY p.OwnerUserId
),
UserPostTagAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(t.tag) AS TagName,
        SUM(p.Score) AS TagTotalScore
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId, TRIM(t.tag)
),
RankedUserTopTags AS (
    SELECT
        uta.UserId,
        uta.TagName,
        uta.TagTotalScore,
        ROW_NUMBER() OVER (PARTITION BY uta.UserId ORDER BY uta.TagTotalScore DESC, uta.TagName ASC) AS TagRank
    FROM UserPostTagAggregates uta
),
PreFilteredUsers AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.OverallActivityScore,
        uas.ActivityLastYearScore,
        uas.UserCreationDate,
        uas.UserLastAccessDate,
        ap.AverageAnswerScore,
        ap.AverageAnswerBodyLength,
        COALESCE(utd.DistinctQuestionTagsCount, 0) AS DistinctQuestionTagsCount,
        COALESCE(ufr.HasReceivedFavoriteVote, 0) AS HasReceivedFavoriteVote,
        DENSE_RANK() OVER (ORDER BY uas.OverallActivityScore DESC, uas.ActivityLastYearScore DESC) AS OverallActivityRank,
        NTILE(10) OVER (ORDER BY uas.OverallActivityScore DESC) AS ActivityDecile,
        LAG(ap.AverageAnswerScore, 1, 0) OVER (ORDER BY uas.OverallActivityScore DESC) AS PrevUserAvgAnswerScore,
        LEAD(ap.AverageAnswerScore, 1, 0) OVER (ORDER BY uas.OverallActivityScore DESC) AS NextUserAvgAnswerScore
    FROM UserActivitySummary uas
    LEFT JOIN AnswerPerformance ap ON uas.UserId = ap.UserId
    LEFT JOIN UserTagDiversity utd ON uas.UserId = utd.UserId
    LEFT JOIN UserFavoriteReceipts ufr ON uas.UserId = ufr.UserId
    WHERE
        uas.OverallActivityScore >= 100
        AND COALESCE(ap.AverageAnswerScore, 0) >= 15
        AND COALESCE(utd.DistinctQuestionTagsCount, 0) >= 5
        AND NOT (
            COALESCE(ap.AverageAnswerBodyLength, 0) < 150
            AND COALESCE(ufr.HasReceivedFavoriteVote, 0) = 0
            AND COALESCE(ap.AnswersCount, 0) > 5
        )
)
SELECT
    p.UserId,
    p.DisplayName,
    p.OverallActivityScore,
    p.ActivityLastYearScore,
    p.AverageAnswerScore,
    p.AverageAnswerBodyLength,
    p.DistinctQuestionTagsCount,
    p.HasReceivedFavoriteVote,
    p.OverallActivityRank,
    p.ActivityDecile,
    p.PrevUserAvgAnswerScore,
    p.NextUserAvgAnswerScore,
    COALESCE(MAX(CASE WHEN rutt.TagRank = 1 THEN rutt.TagName END), 'N/A') AS Top1QuestionTag,
    COALESCE(MAX(CASE WHEN rutt.TagRank = 1 THEN rutt.TagTotalScore END), 0) AS Top1QuestionTagScore,
    COALESCE(MAX(CASE WHEN rutt.TagRank = 2 THEN rutt.TagName END), 'N/A') AS Top2QuestionTag,
    COALESCE(MAX(CASE WHEN rutt.TagRank = 2 THEN rutt.TagTotalScore END), 0) AS Top2QuestionTagScore,
    COALESCE(MAX(CASE WHEN rutt.TagRank = 3 THEN rutt.TagName END), 'N/A') AS Top3QuestionTag,
    COALESCE(MAX(CASE WHEN rutt.TagRank = 3 THEN rutt.TagTotalScore END), 0) AS Top3QuestionTagScore,
    (
        SELECT
            COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = p.UserId
          AND ph.PostHistoryTypeId IN (4, 5, 6)
          AND ph.CreationDate BETWEEN (p.UserLastAccessDate - INTERVAL '90 days') AND p.UserLastAccessDate
    ) AS RecentEditsOnOwnPostsCount,
    (
        SELECT
            COALESCE(AVG(CAST(p_edited.Score AS NUMERIC)), 0)
        FROM PostHistory ph_edit
        JOIN Posts p_edited ON ph_edit.PostId = p_edited.Id
        WHERE ph_edit.UserId = p.UserId
          AND ph_edit.PostHistoryTypeId IN (4, 5, 6)
          AND p_edited.CreationDate BETWEEN (p.UserCreationDate - INTERVAL '1 year') AND p.UserLastAccessDate
          AND (p_edited.OwnerUserId IS DISTINCT FROM p.UserId)
    ) AS AvgScoreOfOtherEditedPosts,
    CASE
        WHEN p.AverageAnswerScore >= (SELECT MAX(AverageAnswerScore) FROM PreFilteredUsers WHERE UserId != p.UserId AND OverallActivityScore > 500) * 0.8
        THEN 'High Performer'
        WHEN p.AverageAnswerScore >= (SELECT AVG(AverageAnswerScore) FROM PreFilteredUsers WHERE OverallActivityScore > 50)
        THEN 'Above Average'
        ELSE 'Average'
    END AS AnswerPerformanceCategory
FROM PreFilteredUsers p
LEFT JOIN RankedUserTopTags rutt ON p.UserId = rutt.UserId AND rutt.TagRank <= 3
GROUP BY
    p.UserId, p.DisplayName, p.OverallActivityScore, p.ActivityLastYearScore, p.AverageAnswerScore,
    p.AverageAnswerBodyLength, p.DistinctQuestionTagsCount, p.HasReceivedFavoriteVote,
    p.OverallActivityRank, p.ActivityDecile, p.PrevUserAvgAnswerScore, p.NextUserAvgAnswerScore,
    p.UserCreationDate, p.UserLastAccessDate
ORDER BY
    p.OverallActivityRank ASC,
    p.AverageAnswerScore DESC,
    p.ActivityLastYearScore DESC
LIMIT 50;