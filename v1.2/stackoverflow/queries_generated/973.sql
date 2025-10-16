-- {"query": "973.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1318} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.TagName] as TagPath
    from Tags t
    where not t.IsModeratorOnly = 1
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.TagPath)
    where not t.IsModeratorOnly = 1
    and array_length(r.TagPath, 1) < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(vt.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes), 0) as TotalDownVotes,
        rank() over (order by coalesce(sum(vt.UpVotes), 0) - coalesce(sum(vt.DownVotes), 0) desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostWithLinkedDuplicates as (
    select
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(
            (select count(*) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3), 0
        ) as DuplicateCount,
        coalesce(
            (
                select string_agg(distinct t.TagName, ', ' order by t.TagName)
                from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tagname
                join Tags t on t.TagName = tagname
            ),
            ''
        ) as TagList
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
RankedPosts as (
    select
        p.PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.OwnerName,
        p.DuplicateCount,
        p.TagList,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRank
    from PostWithLinkedDuplicates p
),
CloseReasonStats as (
    select
        c.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    join Comments c on c.PostId = ph.PostId and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
    group by c.Comment, crt.Name
),
AggregatedUserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        bool_or(b.TagBased::boolean) as HasTagBasedBadges
    from Badges b
    group by b.UserId
)
select
    u.UserId,
    u.DisplayName,
    u.QuestionCount,
    u.AnswerCount,
    u.CommentCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.ReputationRank,
    ab.GoldBadges,
    ab.SilverBadges,
    ab.BronzeBadges,
    ab.HasTagBasedBadges,
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.DuplicateCount,
    rp.TagList,
    cr.CloseReasonName,
    cr.CloseCount,
    string_agg(distinct rth.TagName, ' > ' order by array_length(rth.TagPath, 1)) as RelatedTagHierarchy
from UserActivity u
left join AggregatedUserBadgeStats ab on ab.UserId = u.UserId
left join RankedPosts rp on rp.OwnerUserId = u.UserId and rp.UserPostRank = 1
left join PostHistory ph on ph.PostId = rp.PostId and ph.PostHistoryTypeId = 10
left join CloseReasonStats cr on cr.CloseReasonId = ph.Comment
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(rp.TagList, ', '))
where u.QuestionCount > 0
group by
    u.UserId,
    u.DisplayName,
    u.QuestionCount,
    u.AnswerCount,
    u.CommentCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.ReputationRank,
    ab.GoldBadges,
    ab.SilverBadges,
    ab.BronzeBadges,
    ab.HasTagBasedBadges,
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.DuplicateCount,
    rp.TagList,
    cr.CloseReasonName,
    cr.CloseCount
order by u.ReputationRank
limit 100;