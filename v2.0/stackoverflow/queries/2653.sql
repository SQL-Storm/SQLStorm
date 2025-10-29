-- {"query": "2653.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1325}
with recursive RecursivePosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        0 as Depth,
        cast(p.Id as varchar) as Path,
        cast(null as integer) as ParentId
    from Posts p
    where p.PostTypeId = 1
    union all
    select 
        c.Id,
        c.PostTypeId,
        c.OwnerUserId,
        c.CreationDate,
        rp.Depth + 1,
        rp.Path || '->' || cast(c.Id as varchar),
        c.ParentId
    from Posts c
    join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId = 2
),
RankedAnswers as (
    select 
        rp.Id,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.Depth,
        rp.ParentId,
        p.Score,
        row_number() over (
            partition by rp.ParentId
            order by p.Score desc, rp.CreationDate asc
        ) as AnswerRank
    from RecursivePosts rp
    join Posts p on rp.Id = p.Id
    where rp.Depth > 0
),
UserBadgeStats as (
    select 
        u.Id UserId, 
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        coalesce(sum(b.Class),0) as BadgeScore
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        pl.LinkTypeId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
),
TopLinkedQuestions as (
    select 
        pa.Id as QuestionId,
        pa.Tags,
        count(distinct pa2.Id) as LinkedAnswerCount
    from PostActivityCTE pa
    left join Posts pa2 on pa2.ParentId = pa.Id and pa2.PostTypeId = 2
    where pa.PostTypeId = 1
    group by pa.Id, pa.Tags
),
UserRecentActivity as (
    select 
        u.Id,
        u.DisplayName,
        max(ph.CreationDate) as LastPostHistoryDate,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select 
    u.Id as UserId,
    u.DisplayName,
    r.AnswerRank,
    r.Score as AnswerScore,
    r.Depth,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pa.ViewCount,
    pa.AnswerCount,
    pa.FavoriteCount,
    pa.Tags,
    pa.LinkTypeName,
    coalesce(tra.LinkedAnswerCount,0) as LinkedAnswers,
    ura.CloseReopenEvents,
    ura.UpVotesReceived,
    ura.DownVotesReceived,
    case 
        when ura.LastPostHistoryDate is null then null
        else extract(epoch from (timestamp '2024-10-01 12:34:56' - ura.LastPostHistoryDate)) / 86400
    end as DaysSinceLastActivity,
    (select string_agg(distinct pht.Name || ':' || cast(ph.PostHistoryTypeId as varchar), '|') 
     from PostHistory ph 
     join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id 
     where ph.PostId = r.Id and ph.UserId = r.OwnerUserId and ph.CreationDate > r.CreationDate - interval '30 days') as RecentHistoryTypes,
    case
        when pa.Score is null or pa.Score < 0 then 0
        when pa.Score = 0 then 1
        else (pa.Score * (1 + ubs.GoldBadges * 2) + coalesce(pa.FavoriteCount,0) * 3) / nullif((1 + ura.UpVotesReceived + ura.DownVotesReceived),0)
    end as AdjustedScore,
    avg(r.Score) over (partition by r.OwnerUserId) as AvgUserAnswerScore,
    case when exists (
        select 1 from PostLinks pld 
        where pld.PostId = r.Id and pld.LinkTypeId = 3
    ) then 'Duplicate'
    else 'Original' end as PostStatus
from RankedAnswers r
join Users u on u.Id = r.OwnerUserId
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join PostActivityCTE pa on pa.Id = r.ParentId
left join TopLinkedQuestions tra on tra.QuestionId = r.ParentId
left join UserRecentActivity ura on ura.Id = u.Id
where 
    ( (pa.Tags is not null and position('python' in lower(pa.Tags)) > 0) or pa.Tags is null )
    and (r.Score > (select avg(Score) from RankedAnswers where OwnerUserId = r.OwnerUserId))
group by
    u.Id,
    u.DisplayName,
    r.AnswerRank,
    r.Score,
    r.Depth,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pa.ViewCount,
    pa.AnswerCount,
    pa.FavoriteCount,
    pa.Tags,
    pa.LinkTypeName,
    tra.LinkedAnswerCount,
    ura.CloseReopenEvents,
    ura.UpVotesReceived,
    ura.DownVotesReceived,
    ura.LastPostHistoryDate,
    r.Id,
    r.OwnerUserId,
    r.CreationDate,
    pa.Score,
    pa.Id,
    r.ParentId
order by AdjustedScore desc nulls last, UserId, AnswerRank
limit 50;