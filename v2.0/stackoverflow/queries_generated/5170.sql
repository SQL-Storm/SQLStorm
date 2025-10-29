-- {"query": "5170.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 730} 
WITH
RecentQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.Body,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
TagStats AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN RecentQuestions rq ON rq.Id = p.Id
  GROUP BY TagName
),
TopTags AS (
  SELECT
    ts.TagName,
    ts.PostCount,
    ts.AvgScore,
    ts.TotalViews,
    ROW_NUMBER() OVER (ORDER BY ts.TotalViews DESC, ts.AvgScore DESC) AS rn
  FROM TagStats ts
),
CorrelatedEdits AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.UserDisplayName,
    ph.CreationDate,
    ph.Text,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,14,15,16,24,36)
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    STRING_AGG(CONCAT(lt.Name, '->', CAST(pl.RelatedPostId AS VARCHAR)), ',') AS Links
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(p.ViewCount) AS ViewsGenerated,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  rq.Id AS QuestionId,
  rq.Title AS QuestionTitle,
  rq.CreationDate AS CreatedAt,
  rq.Score AS Score,
  rq.ViewCount AS Views,
  rq.CommentCount AS Comments,
  rq.AnswerCount AS Answers,
  rq.Tags,
  tga.TotalViews AS TagTotalViews,
  tga.AvgScore AS TagAvgScore,
  tga.PostCount AS TagPostCount,
  coalesce(ced.Text, '') AS RecentEditText,
  coalesce(pla.Links, '') AS RelatedLinks,
  ua.UserId AS TopActiveUserId,
  ua.DisplayName AS TopActiveUserName,
  ua.Reputation AS TopActiveUserRep
FROM RecentQuestions rq
LEFT JOIN TopTags tga ON tga.rn = 1
LEFT JOIN CorrelatedEdits ced ON ced.PostId = rq.Id
LEFT JOIN PostLinksAgg pla ON pla.PostId = rq.Id
LEFT JOIN UserActivity ua ON ua.UserId = rq.OwnerUserId
ORDER BY rq.CreationDate DESC
LIMIT 100;