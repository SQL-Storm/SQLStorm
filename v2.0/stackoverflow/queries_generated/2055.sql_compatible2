with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        p.CreationDate,
        coalesce(p.Score,0) as Score,
        rnk.RowNum
    from
        Tags t
        join Posts p on p.Tags like concat('%<', t.TagName, '>%')
        join (
            select
                p2.Id,
                row_number() over (partition by t2.Id order by p2.CreationDate desc) as RowNum
            from Posts p2
            join Tags t2 on p2.Tags like concat('%<', t2.TagName, '>%')
        ) rnk on rnk.Id = p.Id and rnk.RowNum <= 100
),
UserBadgeAggregates as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(b.Id) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostAnswersRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
CloseReasonCounts as (
    select
        cht.Id as CloseReasonId,
        cht.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtype on ph.PostHistoryTypeId = chtype.Id
    join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Id, cht.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        ph.PostId,
        ph.CreationDate,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as ActivityRank,
        lag(ph.PostId) over (partition by u.Id order by ph.CreationDate desc) as PrevPostId
    from Users u
    join PostHistory ph on ph.UserId = u.Id
    where ph.PostHistoryTypeId in (4,5,6)
),
UserActivityDiffs as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.PostId,
        ua.CreationDate,
        coalesce(ua.PrevPostId, -1) as PrevPostId,
        p1.Score as CurrentPostScore,
        p2.Score as PrevPostScore,
        case
            when p1.Score = p2.Score then 0
            when p1.Score > p2.Score then 1
            else -1
        end as ScoreChangeDirection
    from UserActivityWindow ua
    left join Posts p1 on p1.Id = ua.PostId
    left join Posts p2 on p2.Id = ua.PrevPostId
)
select distinct
    t.TagName,
    p.Id as QuestionId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    u.DisplayName as QuestionOwner,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    coalesce(crc.CloseCount,0) as CloseVotesCount,
    coalesce(pa.AnswerId, -1) as TopAnswerId,
    pa.AnswerRank,
    pa.Score as TopAnswerScore,
    ua.ScoreChangeDirection,
    ua.CurrentPostScore,
    ua.PrevPostScore,
    concat(
        substring(p.Title from 1 for 20),
        case when p.Title is null or length(p.Title) < 20 then '' else '...' end
    ) as ShortTitle,
    case
        when p.ClosedDate is null then 'Open'
        else 'Closed'
    end as PostStatus,
    case
        when position('<java>' in p.Tags) > 0 then 'Java'
        when position('<python>' in p.Tags) > 0 then 'Python'
        else 'Other'
    end as LanguageTag,
    coalesce(u.WebsiteUrl, 'No Website') as OwnerWebsite,
    coalesce(u.Location, 'Unknown Location') as OwnerLocation,
    ua.CreationDate as UserActivityCreationDate
from
    RecursiveTagCounts t
    join Posts p on p.Id = t.PostId
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeAggregates uba on uba.UserId = u.Id
    left join CloseReasonCounts crc on crc.CloseReasonId = (
        select cast(ph.Comment as integer) from PostHistory ph
        where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        order by ph.CreationDate desc
        fetch first 1 row only
    )
    left join PostAnswersRanks pa on pa.QuestionId = p.Id and pa.AnswerRank = 1
    left join UserActivityDiffs ua on ua.PostId = p.Id and ua.UserId = u.Id
where
    (p.CreationDate between cast('2024-10-01' as date) - interval '1 year' and cast('2024-10-01' as date))
    and (t.RowNum <= 10)
    and (p.Score > 0 or pa.Score > 0)
group by
    t.TagName,
    p.Id,
    p.Title,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    u.DisplayName,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    crc.CloseCount,
    pa.AnswerId,
    pa.AnswerRank,
    pa.Score,
    ua.ScoreChangeDirection,
    ua.CurrentPostScore,
    ua.PrevPostScore,
    p.ClosedDate,
    p.Tags,
    u.WebsiteUrl,
    u.Location,
    t.RowNum,
    ua.CreationDate
order by
    t.TagName,
    p.Score desc,
    pa.Score desc,
    ua.CreationDate desc;