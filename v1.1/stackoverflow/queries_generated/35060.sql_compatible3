WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HotQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(a.Id) AS AnswerCount,
        array_length(regexp_split_to_array(COALESCE(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), ''), '><'), 1) AS TagCount,
        COALESCE(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '') AS Tags
    FROM
        Posts p
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
        AND p.ViewCount > 1000
        AND p.Score > 5
        AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, COALESCE(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '')
),
PopularTags AS (
    SELECT
        t.TagName,
        t.Count AS UsageCount
    FROM
        Tags t
    WHERE
        t.Count > (SELECT AVG(t2.Count) FROM Tags t2)
    ORDER BY
        t.Count DESC
    LIMIT 20
),
HotQuestionTags AS (
    SELECT
        h.QuestionId,
        tag AS TagName
    FROM
        HotQuestions h,
        regexp_split_to_table(COALESCE(h.Tags, ''), '><') AS tag
),
QuestionTagMatches AS (
    SELECT
        hq.QuestionId,
        COUNT(pt.TagName) AS MatchingPopularTags
    FROM
        HotQuestionTags hq
        JOIN PopularTags pt ON hq.TagName = pt.TagName
    GROUP BY
        hq.QuestionId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalBadges,
    ua.AvgPostScore,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    q.Title AS HotQuestionTitle,
    q.Score AS HotQuestionScore,
    q.ViewCount AS HotQuestionViews,
    COALESCE(qt.MatchingPopularTags, 0) AS MatchingPopularTags,
    q.TagCount AS HotQuestionTagCount,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate
FROM
    UserActivity ua
    LEFT JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
    LEFT JOIN HotQuestions q ON q.QuestionId = p.Id
    LEFT JOIN QuestionTagMatches qt ON qt.QuestionId = q.QuestionId
    LEFT JOIN Badges b ON b.UserId = ua.UserId
WHERE
    q.QuestionId IS NOT NULL
    AND ua.Reputation > 1000
    AND ua.QuestionsPosted >= 5
    AND ua.AnswersPosted >= 10
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalBadges,
    ua.AvgPostScore,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    q.QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    qt.MatchingPopularTags,
    q.TagCount,
    b.Name,
    b.Class,
    b.Date
ORDER BY
    ua.Reputation DESC,
    q.ViewCount DESC,
    q.Score DESC,
    b.Class ASC
LIMIT 100;