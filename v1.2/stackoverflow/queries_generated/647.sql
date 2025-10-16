-- {"query": "647.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1699} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsRequired = 1
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || '>' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on position(t2.TagName in r.Path) = 0 and t2.IsRequired = 1 and t2.Count < r.Count
    where r.Level < 3
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        row_number() over (partition by u.Location order by u.Reputation desc nulls last) as LocRank,
        avg(u.Reputation) over (partition by u.Location) as AvgRepByLoc,
        count(*) over (partition by u.Location) as UsersInLoc,
        coalesce(ub.Gold,0) as GoldBadges,
        coalesce(ub.Silver,0) as SilverBadges,
        coalesce(ub.Bronze,0) as BronzeBadges
    from Users u
    left join (
        select
            UserId,
            max(case when Class = 1 then BadgeCount else 0 end) as Gold,
            max(case when Class = 2 then BadgeCount else 0 end) as Silver,
            max(case when Class = 3 then BadgeCount else 0 end) as Bronze
        from UserBadgeRanks
        group by UserId
    ) ub on u.Id = ub.UserId
    where u.Reputation is not null
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.CreationDate >= current_date - interval '1 year'
),
QuestionsWithCloseReason as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    where ph.CreationDate >= current_date - interval '1 year'
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersProvided,
        count(distinct c.Id) as CommentsMade,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(vt.VoteCount) as TotalVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            v.PostId,
            count(*) as VoteCount
        from Votes v
        where v.VoteTypeId in (2,3)
        group by v.PostId
    ) vt on vt.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostsWithVotesAndBadges as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(ub.Gold,0) as GoldBadges,
        coalesce(ub.Silver,0) as SilverBadges,
        coalesce(ub.Bronze,0) as BronzeBadges
    from Posts p
    left join (
        select
            v.PostId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes v
        group by v.PostId
    ) v on v.PostId = p.Id
    left join (
        select
            b.UserId,
            sum(case when b.Class = 1 then 1 else 0 end) as Gold,
            sum(case when b.Class = 2 then 1 else 0 end) as Silver,
            sum(case when b.Class = 3 then 1 else 0 end) as Bronze
        from Badges b
        group by b.UserId
    ) ub on ub.UserId = p.OwnerUserId
    where p.PostTypeId in (1,2)
)
select
    q.QuestionId,
    q.Title,
    q.QuestionDate,
    q.QuestionScore,
    q.ViewCount,
    q.Tags,
    coalesce(cwr.CloseReasonName, 'Open') as CloseStatus,
    q.AnswerId,
    q.AnswerScore,
    q.AnswerDate,
    q.AnswerOwnerId,
    q.AnswerOwnerName,
    u.DisplayName as QuestionOwner,
    u.Reputation as QuestionOwnerReputation,
    u.Location as QuestionOwnerLocation,
    usr.QuestionsAsked,
    usr.AnswersProvided,
    usr.CommentsMade,
    usr.MaxAnswerScore,
    usr.TotalVotesReceived,
    pvb.UpVotes,
    pvb.DownVotes,
    pvb.GoldBadges,
    pvb.SilverBadges,
    pvb.BronzeBadges,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath,
    case
        when q.QuestionScore > 100 then 'Hot Question'
        when q.QuestionScore between 50 and 100 then 'Popular Question'
        else 'Normal Question'
    end as PopularityCategory,
    dense_rank() over (partition by u.Location order by u.Reputation desc nulls last) as LocationReputationRank,
    case
        when pvb.UpVotes > pvb.DownVotes then 'Positive Reception'
        when pvb.UpVotes = pvb.DownVotes then 'Neutral Reception'
        else 'Negative Reception'
    end as ReceptionCategory
from TopQuestionsWithAnswers q
left join Users u on u.Id = (select OwnerUserId from Posts where Id = q.QuestionId)
left join QuestionsWithCloseReason cwr on cwr.PostId = q.QuestionId
left join UserActivitySummary usr on usr.UserId = u.Id
left join PostsWithVotesAndBadges pvb on pvb.Id = q.AnswerId
left join RecursiveTagHierarchy rh on rh.TagName = substring(q.Tags from '<([^<>]+)>')
where q.AnswerRank = 1
  and (q.Tags is not null and q.Tags <> '')
  and (u.Reputation is not null and u.Reputation > 100)
  and (usr.QuestionsAsked + usr.AnswersProvided) > 10
order by q.QuestionScore desc, q.ViewCount desc
limit 100;