-- {"query": "46068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2230}

WITH RECURSIVE UserInfluence AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) as QuestionCount,
    COUNT(DISTINCT a.Id) as AnswerCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
  LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
  WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TagExpertise AS (
  SELECT 
    p.OwnerUserId,
    tag_element as TagName,
    COUNT(DISTINCT p.Id) as PostsInTag,
    AVG(p.Score) as AvgScore,
    SUM(p.ViewCount) as TotalViews,
    COUNT(DISTINCT b.Id) as TagBadges
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_element
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId 
    AND b.Name = tag_element 
    AND b.TagBased = 1
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '18 months'
  GROUP BY p.OwnerUserId, tag_element
  HAVING COUNT(DISTINCT p.Id) >= 3
),
InteractionNetwork AS (
  SELECT 
    q.OwnerUserId as QuestionOwner,
    a.OwnerUserId as AnswerProvider,
    COUNT(DISTINCT a.Id) as AnswerInteractions,
    COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) as AcceptedAnswers,
    AVG(a.Score) as AvgAnswerScore,
    COUNT(DISTINCT c.Id) as CommentInteractions
  FROM Posts q
  INNER JOIN Posts a ON q.Id = a.ParentId
  LEFT JOIN Comments c ON a.PostId = c.PostId AND c.UserId = q.OwnerUserId
  WHERE q.PostTypeId = 1 
    AND a.PostTypeId = 2
    AND q.OwnerUserId IS NOT NULL
    AND a.OwnerUserId IS NOT NULL
    AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
  GROUP BY q.OwnerUserId, a.OwnerUserId
),
ContentQuality AS (
  SELECT 
    p.Id as PostId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    LENGTH(p.Body) as BodyLength,
    EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600 as ActiveHours,
    COUNT(DISTINCT ph.Id) as EditCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
    COUNT(DISTINCT pl.Id) as LinkedPosts
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.Body, p.LastActivityDate, p.CreationDate
)
SELECT 
  ui.DisplayName,
  ui.Reputation,
  ui.QuestionCount,
  ui.AnswerCount,
  ui.QuestionScore + ui.AnswerScore as TotalScore,
  te_ranked.TopTags,
  te_ranked.TagExpertiseScore,
  COALESCE(int_stats.TotalAnswersReceived, 0) as AnswersReceived,
  COALESCE(int_stats.AcceptedAnswersReceived, 0) as AcceptedAnswersReceived,
  COALESCE(int_stats.TotalAnswersProvided, 0) as AnswersProvided,
  COALESCE(int_stats.AcceptedAnswersProvided, 0) as AcceptedAnswersProvided,
  COALESCE(cq_stats.AvgPostScore, 0) as AvgPostScore,
  COALESCE(cq_stats.AvgViewCount, 0) as AvgViewCount,
  COALESCE(cq_stats.TotalEdits, 0) as TotalEdits,
  COALESCE(badge_stats.GoldBadges, 0) as GoldBadges,
  COALESCE(badge_stats.SilverBadges, 0) as SilverBadges,
  COALESCE(badge_stats.BronzeBadges, 0) as BronzeBadges,
  RANK() OVER (ORDER BY ui.Reputation DESC) as ReputationRank,
  RANK() OVER (ORDER BY ui.QuestionScore + ui.AnswerScore DESC) as ScoreRank
FROM UserInfluence ui
LEFT JOIN LATERAL (
  SELECT 
    string_agg(te.TagName, ', ' ORDER BY te.PostsInTag DESC) as TopTags,
    SUM(te.PostsInTag * te.AvgScore) as TagExpertiseScore
  FROM (
    SELECT * FROM TagExpertise 
    WHERE OwnerUserId = ui.Id 
    ORDER BY PostsInTag DESC, AvgScore DESC 
    LIMIT 5
  ) te
) te_ranked ON true
LEFT JOIN LATERAL (
  SELECT 
    SUM(CASE WHEN QuestionOwner = ui.Id THEN AnswerInteractions ELSE 0 END) as TotalAnswersReceived,
    SUM(CASE WHEN QuestionOwner = ui.Id THEN AcceptedAnswers ELSE 0 END) as AcceptedAnswersReceived,
    SUM(CASE WHEN AnswerProvider = ui.Id THEN AnswerInteractions ELSE 0 END) as TotalAnswersProvided,
    SUM(CASE WHEN AnswerProvider = ui.Id THEN AcceptedAnswers ELSE 0 END) as AcceptedAnswersProvided
  FROM InteractionNetwork
  WHERE QuestionOwner = ui.Id OR AnswerProvider = ui.Id
) int_stats ON true
LEFT JOIN LATERAL (
  SELECT 
    AVG(Score) as AvgPostScore,
    AVG(ViewCount) as AvgViewCount,
    SUM(EditCount) as TotalEdits
  FROM ContentQuality
  WHERE OwnerUserId = ui.Id
) cq_stats ON true
LEFT JOIN LATERAL (
  SELECT 
    COUNT(CASE WHEN Class = 1 THEN 1 END) as GoldBadges,
    COUNT(CASE WHEN Class = 2 THEN 1 END) as SilverBadges,
    COUNT(CASE WHEN Class = 3 THEN 1 END) as BronzeBadges
  FROM Badges
  WHERE UserId = ui.Id
) badge_stats ON true
WHERE ui.QuestionCount + ui.AnswerCount > 0
ORDER BY 
  (ui.Reputation * 0.3 + 
   (ui.QuestionScore + ui.AnswerScore) * 0.4 + 
   COALESCE(te_ranked.TagExpertiseScore, 0) * 0.2 + 
   COALESCE(cq_stats.AvgPostScore, 0) * 50 * 0.1) DESC
LIMIT 100;
