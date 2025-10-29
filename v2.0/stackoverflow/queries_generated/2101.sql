-- {"query": "2101.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2135} 
with RecursiveUserSummary as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        -- total votes user gave by type
        coalesce((select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2),0) as UpVotesGiven,
        coalesce((select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3),0) as DownVotesGiven,
        -- last activity date
        greatest(
            coalesce(u.LastAccessDate,'1900-01-01'),
            (select max(p.LastActivityDate) from Posts p where p.OwnerUserId = u.Id),
            (select max(c.CreationDate) from Comments c where c.UserId = u.Id)
        ) as LastActive
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.LastAccessDate
    union all
    select 
        r.Id,
        r.DisplayName,
        r.Reputation,
        r.CreationDate,
        r.Location,
        r.BadgeCount,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        r.UpVotesGiven,
        r.DownVotesGiven,
        date(r.LastActive,'+1 day')
    from RecursiveUserSummary r
    where false
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreated,
        q.Score as QuestionScore,
        coalesce(q.ViewCount,0) as Views,
        q.Tags,
        q.AnswerCount,
        coalesce(aa.AnswerCount, 0) as ActualAnswerCount,
        coalesce(aa.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(aa.AvgAnswerScore, 0) as AvgAnswerScore,
        q.AcceptedAnswerId,
        pscore.Score as AcceptedAnswerScore,
        u.DisplayName as QuestionOwnerName,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts q
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxAnswerScore,
            avg(Score) as AvgAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) aa on aa.ParentId = q.Id
    left join Posts pscore on pscore.Id = q.AcceptedAnswerId
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
),
TopUserBadges as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        dense_rank() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
    where b.Class = 1
),
UserPostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pl.CreationDate,
        lnk.Name as LinkTypeName,
        p.PostTypeId,
        p.Score,
        p.OwnerUserId
    from PostLinks pl
    join LinkTypes lnk on lnk.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
),
TagAggregates as (
    select
        t.TagName,
        t.Count,
        coalesce(qas.QuestionCount, 0) as QuestionCount,
        coalesce(qas.AvgScore, 0) as AvgQuestionScore,
        coalesce(qas.AvgAnswers, 0) as AvgAnswersPerQuestion
    from Tags t
    left join (
        select
            trim(tag) as TagName,
            count(*) as QuestionCount,
            avg(p.Score) as AvgScore,
            avg(p.AnswerCount) as AvgAnswers
        from Posts p,
        unnest(string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2), '><')
            ) as tag
        where p.PostTypeId = 1
        group by trim(tag)
    ) qas on lower(t.TagName) = lower(qas.TagName)
),
WinRankedQuestions as (
    select
        qas.*,
        row_number() over (partition by qas.OwnerUserId order by qas.QuestionScore desc) as UserQuestionRank,
        rank() over (order by qas.QuestionScore desc) as GlobalQuestionRank,
        ntile(5) over (order by qas.Views desc) as ViewQuintile
    from QuestionAnswerStats qas
),
ClosedReasonDetails as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where ph.PostHistoryTypeId = 10
),
HighActivityQuestions as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.LastActivityDate,
        count(c.Id) as CommentCount,
        max(ph.CreationDate) as LastHistoryEdit
    from Posts q
    left join Comments c on c.PostId = q.Id
    left join PostHistory ph on ph.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.LastActivityDate
),
ComplexUserScores as (
    select
        u.Id,
        u.DisplayName,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesReceived,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(avg(p.Score) filter (where p.PostTypeId IN (1,2)), 0) as AvgPostScore,
        coalesce(max(p.Score) filter (where p.PostTypeId IN (1,2)), 0) as MaxPostScore,
        max(u.Reputation) as Reputation,
        case when max(u.Location) is null or length(trim(u.Location)) = 0 then 'Unknown' else u.Location end as NormLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Location
)
select 
    wuq.Id as QuestionId,
    wuq.Title,
    wuq.QuestionScore,
    wuq.Views,
    wuq.AnswerCount,
    wuq.MaxAnswerScore,
    wuq.AvgAnswerScore,
    wuq.AcceptedAnswerId,
    wuq.AcceptedAnswerScore,
    wuq.IsClosed,
    crd.CloseReasonName,
    ucs.DisplayName as QuestionOwner,
    ucs.Reputation as OwnerReputation,
    ucs.QuestionCount as OwnerQuestionCount,
    ucs.AnswerCount as OwnerAnswerCount,
    ucs.UpVotesReceived,
    ucs.DownVotesReceived,
    ucs.FavoritesReceived,
    ucs.AvgPostScore,
    ucs.MaxPostScore,
    ucs.NormLocation,
    tas.TagName,
    tas.Count as TagPopularity,
    tas.QuestionCount as TagQuestionCount,
    tas.AvgQuestionScore as TagAvgScore,
    tas.AvgAnswersPerQuestion as TagAvgAnswers,
    ul.PostId as LinkedPostId,
    ul.RelatedPostId as RelatedPostId,
    ul.LinkTypeName,
    ul.PostTypeId as RelatedPostTypeId,
    ul.Score as RelatedPostScore,
    ul.OwnerUserId as RelatedPostOwnerUserId,
    hq.CommentCount as TotalCommentsOnQuestion,
    hq.LastHistoryEdit as LastPostHistoryEdit,
    topb.BadgeName as LatestGoldBadgeName,
    topb.Date as LatestGoldBadgeDate,
    wuq.UserQuestionRank,
    wuq.GlobalQuestionRank,
    wuq.ViewQuintile
from WinRankedQuestions wuq
left join ComplexUserScores ucs on ucs.Id = wuq.OwnerUserId
left join TagAggregates tas on lower(tas.TagName) in (
    select lower(trim(tag))
    from unnest(string_to_array(substring(wuq.Tags, 2, length(wuq.Tags)-2), '><')) as tag
)
left join UserPostLinks ul on ul.PostId = wuq.Id and ul.LinkTypeId = 1
left join ClosedReasonDetails crd on crd.PostId = wuq.Id
left join HighActivityQuestions hq on hq.Id = wuq.Id
left join (
    select ub.UserId, ub.BadgeName, ub.Date
    from TopUserBadges ub
    where ub.BadgeRank = 1
) topb on topb.UserId = wuq.OwnerUserId
where wuq.QuestionScore > (
    select avg(Score) from Posts where PostTypeId = 1
)
and (wuq.Views > 1000 or wuq.AnswerCount > 5)
order by wuq.QuestionScore desc, wuq.Views desc
limit 100;