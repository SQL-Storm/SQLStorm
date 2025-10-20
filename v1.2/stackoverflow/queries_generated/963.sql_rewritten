-- {"query": "963.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1296} 
with UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(u.Location, 'Unknown') as Location,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl
),
RecentPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn_by_user
    from Posts p
    where p.CreationDate > cast('2024-10-01' as date) - interval '1 year'
),
HighImpactUsers as (
    select ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.CommentCount,
           ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
           coalesce(p.RankAvgScore, 0) as AvgTopPostScore
    from UserActivity ua
    left join (
        select OwnerUserId,
            avg(Score) as RankAvgScore
        from Posts
        where CreationDate > cast('2024-10-01' as date) - interval '1 year'
        group by OwnerUserId
        having avg(Score) > 10
    ) p on p.OwnerUserId = ua.UserId
    where (ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges) > 5
      and ua.Reputation > 1000
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3  -- duplicates
),
QuestionCloseReasons as (
    select ph.PostId, crt.Name as CloseReasonName, ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
      and ph.Comment ~ '^\d+$' -- ensure comment is numeric close reason id
)
select 
    hiu.UserId,
    hiu.DisplayName,
    hiu.Reputation,
    hiu.QuestionCount,
    hiu.AnswerCount,
    hiu.CommentCount,
    hiu.GoldBadges,
    hiu.SilverBadges,
    hiu.BronzeBadges,
    hiu.AvgTopPostScore,
    rp.Id as RecentPostId,
    rp.PostTypeId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    array_to_string(string_to_array(coalesce(rp.Tags,''), '><'), ', ') as ParsedTags,
    coalesce(dpl.RelatedPostId, -1) as DuplicateOfPostId,
    dpl.CreationDate as DuplicateLinkCreated,
    dpl.LinkTypeName,
    qcr.CloseReasonName,
    qcr.CloseDate,
    row_number() over (partition by hiu.UserId order by rp.Score desc nulls last, rp.ViewCount desc nulls last) as PostRank,
    case 
        when rp.Score < 0 then 'Negative'
        when rp.Score between 0 and 10 then 'Moderate'
        when rp.Score > 10 then 'High'
        else 'Unknown'
    end as ScoreCategory,
    case 
        when rp.ViewCount is null or rp.ViewCount < 100 then 'LowViews'
        when rp.ViewCount between 100 and 1000 then 'MediumViews'
        when rp.ViewCount > 1000 then 'HighViews'
        else 'UnknownViews'
    end as ViewCategory,
    -- correlated subquery to find count of comments on this post by distinct users excluding owner
    (select count(distinct csub.UserId) 
     from Comments csub 
     where csub.PostId = rp.Id and csub.UserId is not null and csub.UserId <> hiu.UserId) as DistinctCommentersExclOwner,
    -- window aggregate to calculate moving average of scores per user posts ordered by creation date
    avg(rp.Score) over (partition by hiu.UserId order by rp.CreationDate rows between 4 preceding and current row) as MovingAvgScoreLast5Posts
from HighImpactUsers hiu
left join RecentPosts rp on rp.OwnerUserId = hiu.UserId and rp.rn_by_user <= 10
left join DuplicateLinks dpl on dpl.PostId = rp.Id
left join QuestionCloseReasons qcr on qcr.PostId = rp.Id
where rp.Id is not null
order by hiu.Reputation desc, hiu.UserId, rp.Score desc
limit 200;