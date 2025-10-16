WITH UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedQuestionsCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgScore,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)) ELSE NULL END, ', ') FILTER (WHERE p.PostTypeId = 1) AS QuestionTags,
        MAX(CASE WHEN p.LastActivityDate IS NOT NULL THEN p.LastActivityDate END) AS LatestActivity
    FROM Posts p
    GROUP BY p.OwnerUserId
),
TopTagsPerUser AS (
    SELECT 
        t.UserId,
        t.TagName,
        t.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY t.UserId ORDER BY t.AnswerCount DESC) AS TagRank
    FROM (
        SELECT 
            p.OwnerUserId AS UserId,
            tag AS TagName,
            COUNT(*) AS AnswerCount
        FROM Posts p,
        LATERAL (
            SELECT TRIM(tk) AS tag
            FROM ( 
                -- split tags like "<tag1><tag2>" into rows
                SELECT REGEXP_SPLIT_TO_TABLE(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><') AS tk
            ) s
        ) split
        WHERE p.PostTypeId = 2
        GROUP BY p.OwnerUserId, tag
    ) t
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ups.QuestionsCount, 0) AS QuestionsCount,
    COALESCE(ups.AnswersCount, 0) AS AnswersCount,
    COALESCE(ups.AcceptedQuestionsCount, 0) AS AcceptedQuestionsCount,
    COALESCE(ups.AvgScore, 0) AS AvgScore,
    ups.QuestionTags,
    ups.LatestActivity,
    tt.TagName AS TopTag,
    tt.AnswerCount AS TopTagAnswerCount,
    RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(ubs.TotalBadges, 0) DESC) AS UserRank,
    CASE 
        WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN SUBSTRING(u.AboutMe FROM 1 FOR 100) || '...'
        ELSE COALESCE(u.AboutMe, 'No description')
    END AS AboutMeSnippet,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score > 5) AS HighScoreComments,
    (SELECT STRING_AGG(vt.Name, ', ') FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.UserId = u.Id GROUP BY v.UserId) AS VoteTypesGiven
FROM Users u
LEFT JOIN UserBadgeCounts ubs ON u.Id = ubs.UserId
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN TopTagsPerUser tt ON u.Id = tt.UserId AND tt.TagRank = 1
WHERE u.Reputation > 1000
  AND (COALESCE(ubs.TotalBadges, 0) > 10 OR COALESCE(ups.AnswersCount, 0) > 50)
  AND u.Id IN (
      SELECT p.OwnerUserId 
      FROM Posts p 
      WHERE p.AcceptedAnswerId IS NOT NULL 
      GROUP BY p.OwnerUserId 
      HAVING COUNT(*) > 5
  )
  AND EXISTS (
      SELECT 1 FROM PostHistory ph 
      WHERE ph.UserId = u.Id 
      AND ph.PostHistoryTypeId IN (1,2,4,5)
  )
ORDER BY UserRank
LIMIT 10;