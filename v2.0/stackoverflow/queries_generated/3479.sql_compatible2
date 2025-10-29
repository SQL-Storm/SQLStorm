WITH TopTags AS (
    SELECT t.TagName, t.Count
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
    ORDER BY t.Count DESC
    LIMIT 10
),
QuestionInfo AS (
    SELECT
        p.Id                                   AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score                                AS QuestionScore,
        p.ViewCount,
        p.FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0)        AS AcceptedAnswerId,
        u.Id                                   AS OwnerUserId,
        u.Reputation,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.ParentId = p.Id AND a.PostTypeId = 2)                                    AS AnswerCount,
        (SELECT AVG(a.Score) 
         FROM Posts a 
         WHERE a.ParentId = p.Id AND a.PostTypeId = 2)                                    AS AvgAnswerScore,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2)                                      AS UpVoteCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 3)                                      AS DownVoteCount,
        (SELECT STRING_AGG(b.Name, ',')
         FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 1)                                           AS GoldBadges
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
TagQuestionLink AS (
    SELECT
        qi.QuestionId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(qi.Tags, '><'))) AS Tag
    FROM QuestionInfo qi
),
TagAggregates AS (
    SELECT
        tql.Tag,
        COUNT(*)                                    AS QCount,
        AVG(qi.QuestionScore)                      AS AvgQScore,
        SUM(qi.ViewCount)                          AS TotalViews,
        SUM(qi.FavoriteCount)                      AS TotalFavorites,
        AVG(qi.AnswerCount)                        AS AvgAnswersPerQ,
        AVG(qi.AvgAnswerScore)                     AS AvgAnswerScore,
        SUM(qi.UpVoteCount)                        AS TotalUpVotes,
        SUM(qi.DownVoteCount)                      AS TotalDownVotes,
        STRING_AGG(DISTINCT qi.GoldBadges, ',')    AS GoldBadgeOwners
    FROM TagQuestionLink tql
    JOIN QuestionInfo qi ON tql.QuestionId = qi.QuestionId
    GROUP BY tql.Tag
),
RankedTags AS (
    SELECT
        ta.Tag,
        ta.QCount,
        ta.AvgQScore,
        ta.TotalViews,
        ta.TotalFavorites,
        ta.AvgAnswersPerQ,
        ta.AvgAnswerScore,
        ta.TotalUpVotes,
        ta.TotalDownVotes,
        ta.GoldBadgeOwners,
        ROW_NUMBER() OVER (ORDER BY ta.QCount DESC) AS Rank
    FROM TagAggregates ta
    WHERE ta.Tag IN (SELECT TagName FROM TopTags)
),
VeteranUsers AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id)                            AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        MAX(b.Date)                            AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.CreationDate < (DATE '2024-10-01' - INTERVAL '5' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 5
),
LatestQuestionOwner AS (
    SELECT qi.OwnerUserId
    FROM QuestionInfo qi
    ORDER BY qi.CreationDate DESC
    LIMIT 1
)
SELECT
    rt.Tag,
    rt.Rank,
    rt.QCount,
    rt.AvgQScore,
    rt.TotalViews,
    rt.TotalFavorites,
    rt.AvgAnswersPerQ,
    rt.AvgAnswerScore,
    rt.TotalUpVotes,
    rt.TotalDownVotes,
    COALESCE(rt.GoldBadgeOwners, 'None')       AS GoldBadgeOwners,
    CASE
        WHEN rt.TotalViews > 100000 THEN 'Hot'
        WHEN rt.TotalViews > 50000  THEN 'Warm'
        ELSE                           'Cold'
    END                                        AS PopularityTier,
    (SELECT COUNT(*)
     FROM Posts p
     LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
     WHERE p.PostTypeId = 1
       AND p.Tags ILIKE '%' || rt.Tag || '%'
       AND pl.Id IS NULL)                    AS UnlinkedQuestionCount,
    vu.UserId,
    vu.DisplayName AS VeteranDisplayName,
    vu.Reputation  AS VeteranReputation,
    vu.TotalBadges,
    vu.GoldBadgeCount,
    vu.LastBadgeDate
FROM RankedTags rt
LEFT JOIN LatestQuestionOwner lq ON TRUE
LEFT JOIN VeteranUsers vu
    ON vu.UserId = lq.OwnerUserId
WHERE rt.Tag IS NOT NULL
GROUP BY
    rt.Tag,
    rt.Rank,
    rt.QCount,
    rt.AvgQScore,
    rt.TotalViews,
    rt.TotalFavorites,
    rt.AvgAnswersPerQ,
    rt.AvgAnswerScore,
    rt.TotalUpVotes,
    rt.TotalDownVotes,
    rt.GoldBadgeOwners,
    vu.UserId,
    vu.DisplayName,
    vu.Reputation,
    vu.TotalBadges,
    vu.GoldBadgeCount,
    vu.LastBadgeDate
ORDER BY rt.Rank;