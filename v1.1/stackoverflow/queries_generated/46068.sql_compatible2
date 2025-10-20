WITH RECURSIVE UserInfluence AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
  LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
  WHERE u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TagExpertise AS (
  SELECT 
    p.OwnerUserId AS OwnerUserId,
    tag_element AS TagName,
    COUNT(DISTINCT p.Id) AS PostsInTag,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT b.Id) AS TagBadges
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_element
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId 
    AND b.Name = tag_element 
    AND b.TagBased = TRUE
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '18 months'
  GROUP BY p.OwnerUserId, tag_element
  HAVING COUNT(DISTINCT p.Id) >= 3
),
InteractionNetwork AS (
  SELECT 
    q.OwnerUserId AS QuestionOwner,
    a.OwnerUserId AS AnswerProvider,
    COUNT(DISTINCT a.Id) AS AnswerInteractions,
    COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) AS AcceptedAnswers,
    AVG(a.Score) AS AvgAnswerScore,
    COUNT(DISTINCT c.Id) AS CommentInteractions
  FROM Posts q
  INNER JOIN Posts a ON q.Id = a.ParentId
  LEFT JOIN Comments c ON a.Id = c.PostId AND c.UserId = q.OwnerUserId
  WHERE q.PostTypeId = 1 
    AND a.PostTypeId = 2
    AND q.OwnerUserId IS NOT NULL
    AND a.OwnerUserId IS NOT NULL
    AND q.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
  GROUP BY q.OwnerUserId, a.OwnerUserId
),
ContentQuality AS (
  SELECT 
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    LENGTH(p.Body) AS BodyLength,
    EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600 AS ActiveHours,
    COUNT(DISTINCT ph.Id) AS EditCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
    COUNT(DISTINCT pl.Id) AS LinkedPosts
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.Body, p.LastActivityDate, p.CreationDate
)
SELECT 
  ui.DisplayName,
  ui.Reputation,
  ui.QuestionCount,
  ui.AnswerCount,
  ui.QuestionScore + ui.AnswerScore AS TotalScore,
  te_ranked.TopTags,
  te_ranked.TagExpertiseScore,
  COALESCE(int_stats.TotalAnswersReceived, 0) AS AnswersReceived,
  COALESCE(int_stats.AcceptedAnswersReceived, 0) AS AcceptedAnswersReceived,
  COALESCE(int_stats.TotalAnswersProvided, 0) AS AnswersProvided,
  COALESCE(int_stats.AcceptedAnswersProvided, 0) AS AcceptedAnswersProvided,
  COALESCE(cq_stats.AvgPostScore, 0) AS AvgPostScore,
  COALESCE(cq_stats.AvgViewCount, 0) AS AvgViewCount,
  COALESCE(cq_stats.TotalEdits, 0) AS TotalEdits,
  COALESCE(badge_stats.GoldBadges, 0) AS GoldBadges,
  COALESCE(badge_stats.SilverBadges, 0) AS SilverBadges,
  COALESCE(badge_stats.BronzeBadges, 0) AS BronzeBadges,
  RANK() OVER (ORDER BY ui.Reputation DESC) AS ReputationRank,
  RANK() OVER (ORDER BY ui.QuestionScore + ui.AnswerScore DESC) AS ScoreRank
FROM UserInfluence ui
LEFT JOIN LATERAL (
  SELECT 
    string_agg(te.TagName, ', ' ORDER BY te.PostsInTag DESC) AS TopTags,
    SUM(te.PostsInTag * te.AvgScore) AS TagExpertiseScore
  FROM (
    SELECT OwnerUserId, TagName, PostsInTag, AvgScore, TotalViews, TagBadges
    FROM TagExpertise 
    WHERE OwnerUserId = ui.Id 
    ORDER BY PostsInTag DESC, AvgScore DESC 
    LIMIT 5
  ) te
) te_ranked ON TRUE
LEFT JOIN LATERAL (
  SELECT 
    SUM(CASE WHEN QuestionOwner = ui.Id THEN AnswerInteractions ELSE 0 END) AS TotalAnswersReceived,
    SUM(CASE WHEN QuestionOwner = ui.Id THEN AcceptedAnswers ELSE 0 END) AS AcceptedAnswersReceived,
    SUM(CASE WHEN AnswerProvider = ui.Id THEN AnswerInteractions ELSE 0 END) AS TotalAnswersProvided,
    SUM(CASE WHEN AnswerProvider = ui.Id THEN AcceptedAnswers ELSE 0 END) AS AcceptedAnswersProvided
  FROM InteractionNetwork
  WHERE QuestionOwner = ui.Id OR AnswerProvider = ui.Id
) int_stats ON TRUE
LEFT JOIN LATERAL (
  SELECT 
    AVG(Score) AS AvgPostScore,
    AVG(ViewCount) AS AvgViewCount,
    SUM(EditCount) AS TotalEdits
  FROM ContentQuality
  WHERE OwnerUserId = ui.Id
) cq_stats ON TRUE
LEFT JOIN LATERAL (
  SELECT 
    COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges
  WHERE UserId = ui.Id
) badge_stats ON TRUE
WHERE ui.QuestionCount + ui.AnswerCount > 0
ORDER BY 
  (ui.Reputation * 0.3 + 
   (ui.QuestionScore + ui.AnswerScore) * 0.4 + 
   COALESCE(te_ranked.TagExpertiseScore, 0) * 0.2 + 
   COALESCE(cq_stats.AvgPostScore, 0) * 50 * 0.1) DESC
LIMIT 100;