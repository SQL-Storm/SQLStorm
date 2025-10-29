-- {"query": "2741.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1545}
with RecursiveCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn,
        coalesce(p.Tags, '') as Tags,
        count(c.Id) over (partition by p.Id) as CommentCountAgg,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1,2)
),
AcceptedAnswerScores as (
    select
        p.Id as QuestionId,
        p.Title as QuestionTitle,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore
    from Posts p
    left join Posts aa on p.AcceptedAnswerId = aa.Id and aa.PostTypeId = 2
    where p.PostTypeId = 1
),
TagExploded as (
    select
        Id,
        unnest(string_to_array(substring(Tags from 2 for char_length(Tags) - 2), '><')) as Tag
    from Posts
    where Tags is not null and Tags != ''
),
UserBadgeCounts as (
    select 
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
),
PostLinkAgg as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        lag(p.CreationDate) over (partition by u.Id order by p.CreationDate) as PrevPostDate,
        lead(p.CreationDate) over (partition by u.Id order by p.CreationDate) as NextPostDate
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
ComplexFilteredPosts as (
    select p.*
    from Posts p
    where 
        (
            (p.Score > 0 and (p.ViewCount / nullif(p.Score,0)) > 50)
            or
            (p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year' and p.AnswerCount > 3)
        )
        and
        (
            p.Tags ilike '%sql%' or p.Tags ilike '%performance%' or p.Title ilike '%index%'
            or exists (
                select 1 from Comments c where c.PostId = p.Id and c.Text ilike '%performance%'
            )
        )
),
UserScoreRank as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        sum(p.Score) as TotalPostScore,
        dense_rank() over (order by sum(p.Score) desc) as ScoreRank
    from Users u
    left join Posts p on u.Id = p.OwnerUserId and p.Score is not null
    group by u.Id, u.DisplayName, u.Reputation
    having sum(p.Score) > 1000
),
CombinedResult as (
    select
        f.Id as PostId,
        f.Title,
        f.CreationDate,
        f.Score,
        f.ViewCount,
        f.Tags,
        u.DisplayName as OwnerDisplayName,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        pla.DuplicateCount,
        pla.LinkedCount,
        crc.CloseReasonName,
        crc.CloseCount,
        aa.AcceptedAnswerScore,
        usr.ScoreRank
    from ComplexFilteredPosts f
    left join Users u on f.OwnerUserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join PostLinkAgg pla on pla.PostId = f.Id
    left join CloseReasonCounts crc on crc.PostId = f.Id
    left join AcceptedAnswerScores aa on aa.QuestionId = f.Id
    left join UserScoreRank usr on usr.Id = u.Id
)
select 
    PostId,
    Title,
    CreationDate,
    Score,
    ViewCount,
    substring(Tags from 1 for 100) as TagsPreview,
    coalesce(OwnerDisplayName, 'Anonymous') as Owner,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    DuplicateCount,
    LinkedCount,
    CloseReasonName,
    CloseCount,
    AcceptedAnswerScore,
    ScoreRank,
    concat('Rank_', ScoreRank) as ScoreRankLabel,
    case 
        when CloseCount is null then 'Open' 
        else 'Closed' 
    end as PostStatus,
    coalesce(CloseReasonName, 'N/A') as CloseReason,
    case 
        when CloseCount > 5 then 'Highly Closed' 
        when CloseCount between 1 and 5 then 'Moderately Closed' 
        else 'Not Closed' 
    end || ' - ' || coalesce(NULLIF(trim(Title), ''), 'No Title') as StatusWithTitle,
    avg(Score) over (order by CreationDate rows between 10 preceding and current row) as MovingAvgScore10,
    (
        select max(u2.Reputation)
        from Users u2
        join Posts p2 on p2.OwnerUserId = u2.Id
        join PostHistory ph2 on ph2.PostId = p2.Id and ph2.PostHistoryTypeId = 10
        join CloseReasonTypes crt2 on cast(ph2.Comment as integer) = crt2.Id
        where crt2.Name = combined.CloseReasonName
    ) as MaxRepInCloseReasonGroup
from CombinedResult combined
order by ScoreRank, Score desc, CreationDate desc
limit 100;