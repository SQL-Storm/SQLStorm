-- {"query": "2650.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1625} 
with RecursivePostHierarchy as (
    select 
        p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
        1 as Level,
        cast(p.Id as varchar(1000)) as Path
    from Posts p
    where p.PostTypeId = 1 -- Questions
    union all
    select 
        c.Id, c.PostTypeId, c.ParentId, c.CreationDate, c.Score, c.ViewCount, c.OwnerUserId,
        r.Level + 1,
        r.Path || '->' || cast(c.Id as varchar(1000))
    from Posts c
    join RecursivePostHierarchy r on c.ParentId = r.Id
    where c.PostTypeId = 2 -- Answers
      and r.Level < 5
),
AggregatedVotes as (
    select 
        v.PostId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
        sum(case when vt.Name = 'BountyStart' then coalesce(v.BountyAmount, 0) else 0 end) as TotalBountyStarted,
        max(v.CreationDate) filter (where vt.Name = 'Close') as LastCloseVoteDate
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
LatestPostHistory as (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn,
        ph.UserId, ph.UserDisplayName, ph.Comment
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
),
UserBadgesRanked as (
    select 
        b.UserId, b.Name, b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as rn
    from Badges b
),
UserActivityWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        count(distinct ph.Id) as TotalEdits,
        max(ph.CreationDate) as LastEditDate,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId in (4,5,6)
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.Location
),
TagUsage as (
    select 
        tag,
        count(*) as UsageCount,
        avg(p.Score) as AvgPostScore,
        max(p.ViewCount) as MaxViewCount
    from Posts p,
    lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
    where p.Tags is not null and p.PostTypeId = 1
    group by tag
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, p1.Title as PostTitle, p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
),
ComplexUserStats as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.TotalEdits,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        case 
            when ua.AnswersCount = 0 then null
            else round(cast(ua.QuestionsCount as numeric) / ua.AnswersCount, 2)
        end as QtoARatio,
        row_number() over (order by ua.Reputation desc, ua.AnswersCount desc) as UserRank,
        ts.UsageCount as FavoriteTagCount,
        ts.AvgPostScore as FavoriteTagAvgScore,
        ts.MaxViewCount as FavoriteTagMaxView
    from UserActivityWindow ua
    left join Lateral (
        select tag as fav_tag
        from Posts p2
        cross join lateral unnest(string_to_array(substring(p2.Tags from 2 for char_length(p2.Tags) - 2), '><')) as tag
        where p2.OwnerUserId = ua.Id
        group by tag
        order by count(*) desc
        limit 1
    ) fav on true
    left join TagUsage ts on ts.tag = fav.fav_tag
)
select
    c.UserRank,
    c.DisplayName,
    c.Reputation,
    c.Location,
    c.QuestionsCount,
    c.AnswersCount,
    c.TotalEdits,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    coalesce(c.QtoARatio, 0) as QtoARatio,
    coalesce(c.FavoriteTagCount, 0) as FavoriteTagCount,
    coalesce(c.FavoriteTagAvgScore, 0) as FavoriteTagAvgScore,
    coalesce(c.FavoriteTagMaxView, 0) as FavoriteTagMaxView,
    phh.Comment as LastCloseReason,
    alv.UpVotes,
    alv.DownVotes,
    alv.TotalBountyStarted,
    alv.LastCloseVoteDate,
    string_agg(distinct concat_ws('=', lt.Name, pl.RelatedPostId), ', ' order by lt.Name) as DuplicateLinksSummary
from ComplexUserStats c
left join Posts p on p.OwnerUserId = c.Id and p.PostTypeId = 1
left join LatestPostHistory phh on phh.PostId = p.Id and phh.rn = 1 and phh.PostHistoryTypeId = 10
left join AggregatedVotes alv on alv.PostId = p.Id
left join PostLinks pl on pl.PostId = p.Id
left join LinkTypes lt on pl.LinkTypeId = lt.Id
where c.Reputation > 1000
and (c.GoldBadges + c.SilverBadges + c.BronzeBadges) >= 3
group by 
  c.UserRank, c.DisplayName, c.Reputation, c.Location, c.QuestionsCount, c.AnswersCount, c.TotalEdits, 
  c.GoldBadges, c.SilverBadges, c.BronzeBadges, c.QtoARatio, c.FavoriteTagCount, c.FavoriteTagAvgScore, c.FavoriteTagMaxView,
  phh.Comment, alv.UpVotes, alv.DownVotes, alv.TotalBountyStarted, alv.LastCloseVoteDate
order by c.UserRank
limit 50;