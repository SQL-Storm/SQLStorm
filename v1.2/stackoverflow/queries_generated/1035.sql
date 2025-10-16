-- {"query": "1035.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1458} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(u.Location, 'Unknown') as Location,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 500
),
UserBadgesSummary as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TaggedQuestions as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.CreationDate,
        array_agg(distinct t.TagName) filter (where t.Id is not null) as TagList,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId
    from Posts p
    left join Tags t on position('<' || t.TagName || '>' in coalesce(p.Tags, '')) > 0
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.AcceptedAnswerId
),
AnswerDetails as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswererName,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    inner join TaggedQuestions q on q.QuestionId = a.ParentId
    left join Users u on u.Id = a.OwnerUserId
    left join (
        select 
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = a.Id
    where a.PostTypeId = 2
),
AnswerRanks as (
    select 
        ad.*,
        rank() over (partition by ad.QuestionId order by ad.Score desc, ad.AnswerCreationDate asc) as AnswerRank,
        lead(ad.Score) over (partition by ad.QuestionId order by ad.Score desc, ad.AnswerCreationDate asc) as NextAnswerScore
    from AnswerDetails ad
),
HighQualityAnswerers as (
    select distinct
        u.Id,
        u.DisplayName,
        count(a.AnswerId) over (partition by u.Id) as TotalHighQualityAnswers
    from Users u
    inner join AnswerRanks a on a.OwnerUserId = u.Id
    where a.Score >= 10 and a.IsAccepted = 1
),
PostHistoryCloseReasonCounts as (
    select 
        ph.Comment as CloseReason,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by ph.Comment
),
FullActivity as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Location,
        ua.Reputation,
        ua.PostId,
        ua.PostTypeId,
        ua.PostScore,
        ua.ViewCount,
        ua.PostCreationDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LastBadgeDate,
        hqa.TotalHighQualityAnswers,
        row_number() over (partition by ua.UserId order by ua.PostCreationDate desc) as PostRecencyRank
    from RecursiveUserActivity ua
    left join UserBadgesSummary ubs on ubs.UserId = ua.UserId
    left join HighQualityAnswerers hqa on hqa.Id = ua.UserId
    where ua.PostId is not null
)
select distinct
    fa.UserId,
    fa.DisplayName,
    fa.Location,
    fa.Reputation,
    fa.GoldBadges,
    fa.SilverBadges,
    fa.BronzeBadges,
    coalesce(fa.TotalHighQualityAnswers, 0) as HighQualityAnswers,
    fa.PostId,
    fa.PostTypeId,
    fa.PostScore,
    fa.ViewCount,
    fa.PostCreationDate,
    phcrc.CloseReason,
    phcrc.ClosedPostsCount,
    case 
        when fa.PostScore > 50 then 'Very High Score'
        when fa.PostScore between 20 and 50 then 'High Score'
        when fa.PostScore between 5 and 19 then 'Medium Score'
        else 'Low Score'
    end as ScoreCategory,
    substring(fa.Location, 1, 15) || case when fa.Location is null then '-Unknown' else '' end as LocationSummary,
    concat('User: ', fa.DisplayName, ' (Reputation: ', fa.Reputation::text, ')') as UserSummary
from FullActivity fa
left join PostHistoryCloseReasonCounts phcrc on phcrc.CloseReason = (
    select ph2.Comment
    from PostHistory ph2
    where ph2.PostId = fa.PostId and ph2.PostHistoryTypeId = 10
    order by ph2.CreationDate desc
    limit 1
)
where fa.PostRecencyRank <= 5
union
select
    null as UserId,
    'ALL' as DisplayName,
    null as Location,
    null as Reputation,
    null as GoldBadges,
    null as SilverBadges,
    null as BronzeBadges,
    null as HighQualityAnswers,
    null as PostId,
    null as PostTypeId,
    avg(p.Score)::int as PostScore,
    avg(p.ViewCount)::int as ViewCount,
    null as PostCreationDate,
    null as CloseReason,
    null as ClosedPostsCount,
    'Average' as ScoreCategory,
    null as LocationSummary,
    'Summary row for benchmarking' as UserSummary
from Posts p
where p.PostTypeId in (1,2)
order by UserId nulls last, PostCreationDate desc;