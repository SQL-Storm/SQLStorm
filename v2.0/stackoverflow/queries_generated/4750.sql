-- {"query": "4750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1385} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestPostEdits AS (
    SELECT
      rph.PostId,
      MAX(CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.UserId ELSE NULL END) AS LatestEditorUserIdTitle,
      MAX(CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.UserId ELSE NULL END) AS LatestEditorUserIdBody,
      MAX(CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.UserId ELSE NULL END) AS LatestEditorUserIdTags,
      MAX(CASE WHEN rph.PostHistoryTypeId = 4 THEN rph.CreationDate ELSE NULL END) AS LatestEditDateTitle,
      MAX(CASE WHEN rph.PostHistoryTypeId = 5 THEN rph.CreationDate ELSE NULL END) AS LatestEditDateBody,
      MAX(CASE WHEN rph.PostHistoryTypeId = 6 THEN rph.CreationDate ELSE NULL END) AS LatestEditDateTags
    FROM RankedPostHistory rph
    WHERE rph.rn = 1
    GROUP BY rph.PostId
  ),
  UserEditCounts AS (
    SELECT
      ph.UserId,
      COUNT(DISTINCT ph.PostId) AS TotalPostsEdited,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
    HAVING COUNT(DISTINCT ph.PostId) > 5 AND SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) > 10
  ),
  HighReputationUsers AS (
    SELECT Id
    FROM Users
    WHERE Reputation > 10000
  ),
  PostsWithCommunityOwnership AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.AnswerCount,
      CASE
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.OwnerUserId = -1 THEN 'Anonymous'
        ELSE u.DisplayName
      END AS OwnerDisplayNameOrStatus,
      COALESCE(lp.LatestEditDateBody, p.LastEditDate) AS EffectiveLastEditDateBody
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN LatestPostEdits lp ON p.Id = lp.PostId
    WHERE p.PostTypeId = 2 -- Answers
  )
SELECT
  pco.Id AS AnswerId,
  pco.OwnerDisplayNameOrStatus,
  pco.CreationDate,
  pco.LastActivityDate,
  pco.Score,
  pco.AnswerCount,
  pco.EffectiveLastEditDateBody,
  uec.TotalPostsEdited,
  uec.TotalEdits,
  CASE
    WHEN pco.Score > 50 THEN 'Highly Scored'
    WHEN pco.AnswerCount > 10 THEN 'High Answer Count'
    WHEN pco.EffectiveLastEditDateBody > DATE('now', '-30 day') THEN 'Recently Edited'
    ELSE 'Standard'
  END AS AnswerCategorization,
  u.DisplayName AS LastEditorDisplayNameForTitle,
  pco.OwnerUserId AS OriginalOwnerUserId,
  CAST(COALESCE(pco.Score * LOG(pco.AnswerCount + 1), 0) AS DECIMAL(10, 2)) AS WeightedScore,
  LENGTH(pco.OwnerDisplayNameOrStatus) AS OwnerNameLength
FROM PostsWithCommunityOwnership pco
LEFT JOIN UserEditCounts uec ON pco.OwnerUserId = uec.UserId
LEFT JOIN Users u ON EXISTS (SELECT 1 FROM LatestPostEdits lpe WHERE lpe.PostId = pco.Id AND lpe.LatestEditorUserIdTitle = u.Id)
WHERE pco.Score > 0
   OR pco.AnswerCount > 0
   OR pco.EffectiveLastEditDateBody IS NOT NULL
UNION
SELECT
  NULL, -- No AnswerId for questions
  p.Title, -- Use Title for questions
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.AnswerCount,
  p.LastEditDate AS EffectiveLastEditDateBody, -- Questions don't have separate body edit dates in this join path
  NULL, -- No UserEditCounts for this part of UNION
  NULL, -- No TotalEdits for this part of UNION
  CASE
    WHEN p.Score > 100 THEN 'Highly Scored Question'
    WHEN p.AnswerCount > 20 THEN 'High Answer Count Question'
    WHEN p.LastEditDate > DATE('now', '-15 day') THEN 'Recently Edited Question'
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed Question'
    ELSE 'Standard Question'
  END AS QuestionCategorization,
  NULL, -- No LastEditorDisplayNameForTitle for this part of UNION
  p.OwnerUserId AS OriginalOwnerUserId,
  CAST(COALESCE(p.Score * LOG(p.ViewCount + 1), 0) AS DECIMAL(10, 2)) AS WeightedScore,
  LENGTH(p.Title) AS OwnerNameLength
FROM Posts p
WHERE p.PostTypeId = 1 -- Questions
  AND (p.Score > 10 OR p.AnswerCount > 5 OR p.ViewCount > 1000)
  AND NOT EXISTS (SELECT 1 FROM HighReputationUsers hru WHERE hru.Id = p.OwnerUserId);
