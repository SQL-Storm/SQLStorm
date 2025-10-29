SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagsInvolved,
    MAX(p.LastActivityDate) AS LastActive,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    CASE
        WHEN u.Reputation > 10000 THEN 'Legendary'
        WHEN u.Reputation > 1000 THEN 'Influential'
        ELSE 'Newcomer'
    END AS ReputationTier,
    COUNT(DISTINCT c.Id) AS CommentCount,
    MAX(b.Date) AS LastBadgeDate
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN (
    SELECT p_inner.Id AS post_id, tag AS tag
    FROM Posts p_inner
    CROSS JOIN LATERAL (
        SELECT TRIM(tag) AS tag
        FROM (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTR(p_inner.Tags, 2, LENGTH(p_inner.Tags) - 2), '><')) AS tag
        ) s
    ) l
) taglist ON taglist.post_id = p.Id
LEFT JOIN Tags t ON t.TagName = taglist.tag
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
    u.AccountId IS NOT NULL
    AND u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP)
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0
ORDER BY
    u.Reputation DESC, LastActive DESC
LIMIT 100;