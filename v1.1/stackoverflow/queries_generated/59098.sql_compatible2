SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) AS BronzeBadges,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (
        SELECT DISTINCT s2.TagName
        FROM (
            SELECT
                CASE
                    WHEN tag = '' THEN NULL
                    ELSE tag
                END AS TagName
            FROM (
                SELECT
                    TRIM(BOTH '<>' FROM p.Tags) AS trimmed_tags
            ) tt
            CROSS JOIN LATERAL (
                SELECT regexp_split_to_table(tt.trimmed_tags, '><') AS tag
            ) s
        ) s2
        WHERE s2.TagName IS NOT NULL AND s2.TagName != ''
    ) t) AS TagList,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
        ELSE 'Unknown'
    END AS PostType,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 2, 3)) AS EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) AS StatusChangeCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) AS LastEditDate,
    (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LastCommentDate,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) AS SuggestedEdits,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBountyAmount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.CreationDate >= DATE '2022-01-01'
    AND p.CreationDate < DATE '2023-01-01'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND p.Score >= 0
    AND p.ViewCount >= 100
    AND p.AnswerCount >= 1
    AND p.CommentCount >= 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 10000;