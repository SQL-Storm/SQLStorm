-- {"query": "949.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1349} 
with RecursiveUserEngagement as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        coalesce(sum(vt_score.Score), 0) as VoteScoreSum,
        row_number() over (order by u.Reputation desc, u.Id asc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select v.PostId, sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end) as Score
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vt_score on vt_score.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), PostWithAnswerStats as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        p.ClosedDate,
        p.FavoriteCount,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        a.CreationDate as AcceptedAnswerCreationDate,
        case 
            when p.AcceptedAnswerId is not null then 1 else 0 
        end as HasAcceptedAnswer,
        row_number() over (partition by p.Id order by a.Score desc nulls last) as AnswerRank
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    where p.PostTypeId = 1
), TagAggregates as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
        count(distinct p.Id) as QuestionCount,
        avg(p.Score) as AverageScore,
        sum(p.ViewCount) as TotalViews
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
    group by 1
), UserBadgeRank as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        dense_rank() over (partition by b.UserId order by b.Class) as BadgeClassRank
    from Badges b
), LatestPostHistoryEdits as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as HistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    where ph.PostHistoryTypeId in (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    order by ph.PostId, ph.CreationDate desc
), PostLinkCounts as (
    select 
        pl.PostId,
        count(case when lt.Name = 'Linked' then 1 end) as LinkedCount,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select 
    rue.UserId,
    rue.DisplayName,
    rue.Reputation,
    rue.QuestionsCount,
    rue.AnswersCount,
    rue.CommentsCount,
    rue.VoteScoreSum,
    rue.UserRank,
    pwas.PostId,
    pwas.Title,
    pwas.Score as QuestionScore,
    pwas.ViewCount,
    pwas.AnswerCount,
    pwas.HasAcceptedAnswer,
    pwas.AcceptedAnswerScore,
    pwas.ClosedDate is not null as IsClosed,
    tagagg.TagName,
    tagagg.QuestionCount as TagQuestionCount,
    tagagg.AverageScore as TagAverageScore,
    tagagg.TotalViews as TagTotalViews,
    ub.BadgeName,
    ub.Class as BadgeClass,
    ub.BadgeClassRank,
    lph.PostHistoryTypeId,
    lph.CreationDate as LastEditDate,
    plk.LinkedCount,
    plk.DuplicateCount,
    -- Window function: rank posts by score per user
    rank() over (partition by rue.UserId order by pwas.Score desc nulls last) as PostScoreRank,
    -- String expression and null logic: formatted title with NULL checks
    case 
        when pwas.Title is null or trim(pwas.Title) = '' then '[no title]'
        else substring(pwas.Title for 60) || case when length(pwas.Title) > 60 then '...' else '' end
    end as ShortTitle,
    -- Complicated predicate: flag high rep users with high scoring posts and recent activity
    case 
        when rue.Reputation > 10000 
            and pwas.Score > 5 
            and coalesce(pwas.ClosedDate, '2100-01-01'::timestamp) > now() - interval '1 year' 
            and rue.LastAccessDate > now() - interval '30 days' then 1
        else 0
    end as ActiveTopContributorFlag
from RecursiveUserEngagement rue
left join PostWithAnswerStats pwas on pwas.OwnerUserId = rue.UserId
left join TagAggregates tagagg on tagagg.TagName = any(string_to_array(substring(pwas.Tags from 2 for length(pwas.Tags)-2), '><'))
left join UserBadgeRank ub on ub.UserId = rue.UserId and ub.BadgeClassRank = 1
left join LatestPostHistoryEdits lph on lph.PostId = pwas.PostId
left join PostLinkCounts plk on plk.PostId = pwas.PostId
where rue.UserRank <= 100
order by rue.UserRank, pwas.Score desc nulls last
limit 500;