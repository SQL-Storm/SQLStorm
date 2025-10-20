WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        CASE WHEN COALESCE(NULLIF(u.WebsiteUrl, ''), 'no_website_negative_flag') = 'no_website_negative_flag' THEN TRUE ELSE FALSE END AS NO_PRIV_WEBSITE,
        regexp_replace(COALESCE(p.Tags, ''), '^<|>$', '') AS TagStringRaw,
        string_to_array(regexp_replace(COALESCE(p.Tags, ''), '^<|>$', ''), '><') AS TagArray,
        ROW_NUMBER() OVER (
            PARTITION BY p.PostTypeId 
            ORDER BY
                CASE WHEN p.AcceptedAnswerId IS NULL THEN 1 ELSE 0 END, 
                p.Score DESC, 
                p.ViewCount DESC,
                p.CreationDate DESC
        ) AS PRank,
        p.AcceptedAnswerId
    FROM 
        Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATE '2019-01-01' AND p.Score >= -5
),

UserBadgesCTE AS (
    SELECT
        UserId,
        CASE Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' WHEN 3 THEN 'Bronze' ELSE 'Unknown' END AS BadgeClass,
        COUNT(*) AS CountBadge,
        STRING_AGG(Name, ', ' ORDER BY Date DESC) AS LatestBadges,
        MAX(Date) AS LastEarned
    FROM 
        Badges
    GROUP BY 
        UserId, Class
),

BadgesSummary AS (
    SELECT 
        UserId,
        MAX(CASE WHEN BadgeClass = 'Gold' THEN CountBadge ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN BadgeClass = 'Silver' THEN CountBadge ELSE 0 END) AS SilverBadges,
        MAX(CASE WHEN BadgeClass = 'Bronze' THEN CountBadge ELSE 0 END) AS BronzeBadges
    FROM UserBadgesCTE
    GROUP BY UserId
),

AnswersWithRanks AS (
    SELECT 
        a.Id, 
        a.ParentId, 
        a.Score, 
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges
    FROM Posts a
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    LEFT JOIN BadgesSummary ubs ON au.Id = ubs.UserId
    WHERE a.PostTypeId = 2
),

UniqueUserVoteFilter AS (
  SELECT DISTINCT UserId FROM Votes    
),

QuestionsOfComplexMeasures AS (
    SELECT    
        rp.Id AS QuestionId,
        rp.TagStringRaw,
        char_length(rp.TagStringRaw) AS TagLength,
        COALESCE(array_length(rp.TagArray, 1), 0) AS TagCount,
        COALESCE(lp_related.RelCount, 0) AS RelatedLinkCount,
        COUNT(DISTINCT vb.Id) AS Votes_for_Question,
        (
           SELECT AVG(a.Score) 
           FROM AnswersWithRanks a
           WHERE a.ParentId = rp.Id 
             AND a.Score > COALESCE((SELECT p2.Score FROM Posts p2 WHERE p2.Id = rp.AcceptedAnswerId), -999999)
        ) AS AvgUsefulAnswersAboveAccepted
    FROM RankedPosts rp
    LEFT JOIN Posts p ON p.Id = rp.Id
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS RelCount
        FROM PostLinks pl
        WHERE pl.PostId = rp.Id
    ) lp_related ON TRUE
    LEFT JOIN Votes vb ON vb.PostId = rp.Id
    GROUP BY
        rp.Id,
        rp.TagStringRaw,
        rp.TagArray,
        lp_related.RelCount,
        p.Id,
        rp.CreationDate,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.PRank,
        rp.NO_PRIV_WEBSITE,
        rp.AcceptedAnswerId
)

SELECT * FROM QuestionsOfComplexMeasures;