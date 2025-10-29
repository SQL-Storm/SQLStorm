WITH top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName ASC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = false AND t.IsRequired = false
),
qualified_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 100
    AND p.Score > 5
),
recent_activity AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.Score AS QuestionScore,
    CA.AnswerCount,
    CA.LastActivityDate AS LastActivityOnQuestion,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    q.Tags
  FROM qualified_posts q
  LEFT JOIN (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(*) AS AnswerCount,
      MAX(a.LastActivityDate) AS LastActivityDate
    FROM Posts a
    WHERE a.PostTypeId = 2 -- Answers
    GROUP BY a.ParentId
  ) CA ON CA.QuestionId = q.Id
  LEFT JOIN Users U ON U.Id = q.OwnerUserId
),
complex_filter AS (
  SELECT
    ra.QuestionId,
    ra.Title,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.QuestionScore,
    ra.AnswerCount,
    ra.LastActivityOnQuestion,
    ra.Reputation AS OwnerReputation,
    ra.Tags,
    CASE
      WHEN ra.AnswerCount IS NULL THEN 0
      ELSE ra.AnswerCount
    END AS TotalAnswers,
    CASE
      WHEN ra.LastActivityOnQuestion IS NULL THEN ra.CreationDate
      ELSE ra.LastActivityOnQuestion
    END AS ActivityMarker,
    ra.CreationDate
  FROM recent_activity ra
  LEFT JOIN Users U2 ON U2.Id = ra.OwnerUserId
),
dedup AS (
  SELECT
    cf.QuestionId,
    cf.Title,
    cf.OwnerUserId,
    cf.OwnerDisplayName,
    cf.OwnerReputation AS Reputation,
    cf.QuestionScore,
    cf.AnswerCount,
    cf.LastActivityOnQuestion,
    cf.TotalAnswers,
    cf.ActivityMarker,
    cf.Tags,
    SUM(CASE WHEN cf.TotalAnswers > 5 THEN 1 ELSE 0 END) OVER (PARTITION BY cf.QuestionId) AS HasManyAnswersFlag
  FROM complex_filter cf
),
final AS (
  SELECT
    d.QuestionId,
    d.Title,
    d.OwnerUserId,
    d.OwnerDisplayName,
    d.Reputation,
    d.QuestionScore,
    d.AnswerCount,
    d.LastActivityOnQuestion AS LastActivityDate,
    d.TotalAnswers,
    d.ActivityMarker,
    d.Tags,
    (
      SELECT STRING_AGG(TagName, ',') FROM (
        SELECT TRIM(tag) AS TagName
        FROM (
          SELECT UNNEST(string_to_array(d.Tags, ',')) AS tag
        ) t1
      ) sub
    ) AS TagList
  FROM dedup d
  ORDER BY d.ActivityMarker DESC, d.QuestionScore DESC
  LIMIT 100
)
SELECT
  f.QuestionId,
  f.Title,
  f.OwnerDisplayName,
  f.Reputation,
  f.QuestionScore,
  f.AnswerCount,
  f.LastActivityDate,
  f.TagList,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = f.QuestionId AND v.VoteTypeId = 6) AS LastCloseVoteDate,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.QuestionId AND v.VoteTypeId = 2) AS UpvotesOnQuestion,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.QuestionId AND pl.LinkTypeId = 1) AS LinkedPosts,
  f.ActivityMarker
FROM final f
JOIN Tags t ON t.TagName = ANY(string_to_array(REPLACE(REPLACE(REPLACE(f.TagList, '[', ''), ']', ''), ' ', ''), ','))
ORDER BY f.ActivityMarker DESC, f.Reputation DESC;