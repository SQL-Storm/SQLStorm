-- {"query": "2726.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1300} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as TotalBountyGranted
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9)
    group by u.Id
    union all
    select
        r.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.CreationDate,
        ru.LastAccessDate,
        ru.QuestionsAsked,
        ru.AnswersGiven,
        ru.CommentsMade,
        ru.TotalBountyGranted
    from RecursiveUserActivity r
    join Users ru on ru.Id = r.UserId
    where ru.Reputation > 10000
    limit 1000 -- to avoid infinite recursion
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        json_agg(distinct case when b.TagBased = 1 then b.Name end) filter (where b.TagBased = 1) as TagBadges
    from Badges b
    group by b.UserId
),
RankedPosts as (
    select
        p.*,
        row_number() over (
            partition by p.OwnerUserId
            order by p.Score desc, p.CreationDate asc
        ) as PostRank,
        rank() over (
            partition by p.PostTypeId
            order by p.Score desc, p.ViewCount desc nulls last
        ) as GlobalPostRank
    from Posts p
    where p.OwnerUserId is not null
),
DuplicateLinkCounts as (
    select
        p.Id as PostId,
        count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by p.Id
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.Id as ExcerptPostId,
        coalesce(string_agg(distinct p.Title, '; ') filter (where p.Title is not null), '') as TagPostTitles
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.Count > 1000 and (t.IsRequired = 1 or t.IsModeratorOnly = 1)
    group by t.TagName, t.Count, p.Id
),
QuestionCloseStats as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as TimesClosed,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedDate,
        count(*) filter (where ph.PostHistoryTypeId = 11) as TimesReopened,
        (select crt.Name from CloseReasonTypes crt where crt.Id = cast(ph.Comment as int) limit 1) as LastCloseReason
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
)
select
    u.Id as UserId,
    u.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    coalesce(ubc.TagBadges::text, '[]') as TagBadges,
    rp.Title as TopScoredPostTitle,
    rp.Score as TopPostScore,
    rp.PostRank as UserPostRank,
    rp.GlobalPostRank,
    dup.DuplicateCount,
    qcs.TimesClosed,
    qcs.TimesReopened,
    qcs.LastCloseReason,
    to_char(u.LastAccessDate, 'YYYY-MM-DD') as LastAccess,
    case 
        when u.Reputation > 100000 then 'Elite'
        when u.Reputation > 10000 then 'Advanced'
        else 'Novice'
    end as ReputationLevel,
    substring(rp.Body from 1 for 100) as PostSnippet,
    length(coalesce(rp.Body, '')) as PostBodyLength,
    regexp_replace(coalesce(rp.Tags, ''), '[<>]', '{}', 'g') as ParsedTags,
    (select array_agg(t.TagName order by t.Count desc) from Tags t where position(t.TagName in coalesce(rp.Tags, '')) > 0) as TagsInPost,
    t.TagsInPost as TagPostTitles
from Users u
inner join RecursiveUserActivity ua on ua.UserId = u.Id
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join RankedPosts rp on rp.OwnerUserId = u.Id and rp.PostRank = 1
left join DuplicateLinkCounts dup on dup.PostId = rp.Id
left join QuestionCloseStats qcs on qcs.PostId = rp.Id
left join LATERAL (
    select string_agg(distinct tt.TagPostTitles, ' | ') as TagsInPost
    from TopTags tt
    where position(tt.TagName in coalesce(rp.Tags, '')) > 0
) t on true
where u.Reputation > 5000 and ua.QuestionsAsked > 5 and rp.Score > 10
order by ua.AnswersGiven desc nulls last, rp.Score desc nulls last
limit 50;