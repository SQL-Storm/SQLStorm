-- {"query": "2932.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1454} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        0 as Level,
        array[t.TagName] as Ancestors
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
  union all
    select
        t.Id,
        t.TagName,
        r.Level + 1,
        r.Ancestors || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on substring(t.TagName, 1, length(r.TagName)) = r.TagName
    where t.Id <> r.Id and not t.TagName = any(r.Ancestors) and r.Level < 3
),
UserPostAgg as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score), 0) as TotalScore,
        coalesce(sum(p.ViewCount), 0) as TotalViews,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
),
UserBadgeCount as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct case when b.TagBased = 1 then b.Name else null end) as DistinctTagBadges
    from Badges b
    group by b.UserId
),
TopPostsByTag as (
    select distinct on (tag, p.OwnerUserId)
        tag,
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        row_number() over (partition by tag order by p.Score desc, p.ViewCount desc) as RankWithinTag
    from
        Posts p
        cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
    where p.PostTypeId = 1
),
PostCloseReasonCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotes
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and crt.Name is not null
    group by ph.PostId, crt.Name
),
PostVotesSum as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserActivityWindows as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.CreationDate,
        p.Score,
        lag(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostDate,
        lead(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostDate,
        count(*) over (partition by p.OwnerUserId order by p.CreationDate rows between 10 preceding and current row) as PostsLast10,
        avg(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 5 preceding and 5 following) as AvgScoreWindow
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
),
UserEmailHashCheck as (
    select
        u.Id,
        u.EmailHash,
        case 
            when u.EmailHash ~ '^[0-9a-f]{32}$' then 'Valid MD5'
            when u.EmailHash is null then 'Missing'
            else 'Invalid'
        end as EmailHashValidity
    from Users u
),
HighlyActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        upa.QuestionCount + upa.AnswerCount as TotalPosts,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ua.PostsLast10,
        ua.AvgScoreWindow,
        u.EmailHash,
        u.Location,
        u.WebsiteUrl,
        u.ProfileImageUrl,
        u.AboutMe
    from Users u
    join UserPostAgg upa on upa.OwnerUserId = u.Id
    left join UserBadgeCount ubc on ubc.UserId = u.Id
    left join UserActivityWindows ua on ua.OwnerUserId = u.Id
    where (upa.QuestionCount + upa.AnswerCount) >= 100
)
select 
    hau.Id as UserId,
    coalesce(hau.DisplayName, '(unknown)') as DisplayName,
    hau.TotalPosts,
    hau.GoldBadges,
    hau.SilverBadges,
    hau.BronzeBadges,
    hau.PostsLast10,
    hau.AvgScoreWindow,
    hau.EmailHashValidity,
    coalesce(hau.Location, 'Unknown') as Location,
    coalesce(hau.WebsiteUrl, '') as Website,
    left(replace(hau.AboutMe, '<', '&lt;'), 100) as AboutMeSnippet,
    tpt.PostId as TopPostId,
    tpt.Title as TopPostTitle,
    tpt.Score as TopPostScore,
    pc.CloseReason,
    pc.CloseVotes,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.Favorites
from
    HighlyActiveUsers hau
    left join (select OwnerUserId, max(Score) as MaxScore from Posts where PostTypeId = 1 group by OwnerUserId) ms on ms.OwnerUserId = hau.Id
    left join Posts p on p.OwnerUserId = hau.Id and p.Score = ms.MaxScore and p.PostTypeId = 1
    left join TopPostsByTag tpt on tpt.PostId = p.Id
    left join PostCloseReasonCount pc on pc.PostId = p.Id
    left join PostVotesSum pvs on pvs.PostId = p.Id
order by
    hau.GoldBadges desc nulls last,
    hau.TotalPosts desc nulls last,
    hau.DisplayName
limit 100;