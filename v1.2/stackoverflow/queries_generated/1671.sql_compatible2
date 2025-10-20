WITH user_badge_counts AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
question_answers_analysis AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.CreationDate AS QuestionDate,
        COUNT(a.Id) AS TotalAnswers,
        COUNT(CASE WHEN a.Score > q.Score THEN 1 END) AS AnswersWithHigherScoreThanQuestion,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) FILTER (WHERE a.Body IS NOT NULL) AS MinAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        STRING_AGG(u.DisplayName, ', ') FILTER (WHERE u.DisplayName IS NOT NULL) AS TopAnswerers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.Score, q.CreationDate
),
post_link_details AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p.ParentId,
        p.PostTypeId,
        rp.PostTypeId AS RelatedPostType
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    INNER JOIN Posts p ON pl.PostId = p.Id
    INNER JOIN Posts rp ON rp.Id = pl.RelatedPostId
),
question_tags AS (
    SELECT 
        Id AS QuestionId,
        LOWER(TRIM(tag)) AS tag
    FROM (
        SELECT 
            Id, 
            regexp_split_to_table(COALESCE(NULLIF(SUBSTRING(tags FROM 2 FOR CHAR_LENGTH(tags) - 2), ''), ''), ',') AS tag 
        FROM Posts 
        WHERE PostTypeId = 1 AND tags IS NOT NULL
    ) a
),
tag_popularity AS (
    SELECT
        t.tag,
        COUNT(DISTINCT t.QuestionId) AS QuestionCount,
        AVG(q.Score) AS AvgQuestionScore,
        SUM(q.AnswerCount) AS TotalAnswersToTaggedQuestions
    FROM question_tags t
    INNER JOIN Posts q ON q.Id = t.QuestionId
    GROUP BY t.tag
    HAVING COUNT(DISTINCT t.QuestionId) > 10
),
top_contributors_per_tag AS (
    SELECT
        t.tag,
        ubc.DisplayName,
        COUNT(*) AS PostsInTag,
        AVG(p.Score) AS AvgPostScore,
        MAX(bc.GoldBadges) AS UserGoldBadges,
        ROW_NUMBER() OVER (PARTITION BY t.tag ORDER BY COUNT(*) DESC, AVG(p.Score) DESC) AS prnk
    FROM question_tags t
    JOIN Posts p ON t.QuestionId = p.Id
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN user_badge_counts bc ON u.Id = bc.Id
    CROSS JOIN LATERAL (
        SELECT displayname FROM user_badge_counts ubc WHERE ubc.Id = u.Id LIMIT 1
    ) ubc
    GROUP BY t.tag, ubc.DisplayName, bc.GoldBadges
),
ranked_users_stay_active_inside_month AS (
    SELECT 
      ubc.Id,
      ubc.DisplayName,
      MAX(us.LastAccessDate) AS most_recent_access,
      (DATE '2024-10-01' - MIN(us.CreationDate)) >= INTERVAL '1 year' AS active_in_last_year,
      COUNT(us.Id) AS session_count_last_30_days
    FROM Users ubc 
    JOIN Users us ON ubc.Id = us.Id
    WHERE us.LastAccessDate >= DATE '2024-10-01' - INTERVAL '30 days'
    GROUP BY ubc.Id, ubc.DisplayName
),
high_performance_answer_search AS (
    SELECT
        a.Id AS AnswerId,
        qp.QuestionId
    FROM Posts a
    JOIN question_answers_analysis qp ON qp.QuestionId = a.ParentId
    WHERE a.PostTypeId = 2
)
SELECT
    uba.Id AS UserId,
    uba.DisplayName AS UserName,
    uba.GoldBadges
FROM user_badge_counts uba
JOIN ranked_users_stay_active_inside_month r ON uba.Id = r.Id;