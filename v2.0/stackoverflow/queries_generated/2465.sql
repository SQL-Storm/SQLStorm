-- {"query": "2465.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1244} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        rank() over (order by u.Reputation desc, u.LastAccessDate desc) as ReputationRank
    from 
        Users u
    left join 
        Posts p on p.OwnerUserId = u.Id
    group by 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select 
        pt.OwnerUserId,
        unnest(string_to_array(substring(pt.Tags from 2 for char_length(pt.Tags)-2), '><')) as TagName
    from 
        Posts pt 
    where 
        pt.PostTypeId = 1 and pt.OwnerUserId is not null
),
UserTagStats as (
    select 
        t.OwnerUserId as UserId,
        t.TagName,
        count(*) as QuestionsPerTag
    from 
        TopTags t
    group by 
        t.OwnerUserId,
        t.TagName
),
UserBadgesRanked as (
    select 
        b.UserId,
        b.Name as BadgeName,
        dense_rank() over (partition by b.UserId order by b.Date desc) as RecentBadgeRank
    from 
        Badges b
),
UserRecentBadges as (
    select 
        u.UserId,
        string_agg(distinct ub.BadgeName, ', ') filter (where ub.RecentBadgeRank <= 3) as RecentBadges
    from 
        RecursiveUserActivity u
    left join 
        UserBadgesRanked ub on ub.UserId = u.UserId
    group by 
        u.UserId
),
QuestionClosedInfo as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.ClosedDate,
        pht.Name as CloseReasonName,
        ph.UserId as CloseVoterUserId,
        u.DisplayName as CloseVoterName
    from 
        Posts p
    left join 
        PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join 
        CloseReasonTypes pht on pht.Id::int = ph.Comment::int
    left join
        Users u on u.Id = ph.UserId
    where 
        p.PostTypeId = 1 and p.ClosedDate is not null
),
AnswerScores as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from 
        Posts a
    where 
        a.PostTypeId = 2
),
QuestionAnswerAggregates as (
    select
        q.Id as QuestionId,
        count(a.AnswerId) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        min(a.CreationDate) as EarliestAnswerDate,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighlyScoredAnswers
    from 
        Posts q
    left join 
        Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where 
        q.PostTypeId = 1
    group by 
        q.Id
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalPostScore,
    ua.ReputationRank,
    coalesce(urt.RecentBadges, 'None') as RecentBadges,
    uts.TagName,
    uts.QuestionsPerTag,
    case when qc.QuestionId is not null then 'Closed' else 'Open' end as QuestionStatus,
    qc.Title as ClosedQuestionTitle,
    qc.CloseReasonName,
    qc.CloseVoterName,
    qaa.TotalAnswers,
    qaa.MaxAnswerScore,
    qaa.EarliestAnswerDate,
    qaa.HighlyScoredAnswers,
    -- Complex string and NULL logic expressions
    concat_ws(' | ',
        ua.DisplayName,
        'Reputation: ' || ua.Reputation,
        'Tags with questions: ' || coalesce(string_agg(distinct uts.TagName, ', ') over (partition by ua.UserId), 'None')
    ) as UserSummary,
    -- Correlated subquery for average score per answer per user
    (select avg(score) from Posts p2 where p2.OwnerUserId = ua.UserId and p2.PostTypeId = 2) as AvgAnswerScore,
    -- Outer join related posts via duplicates and links
    pl.LinkTypeId,
    lt.Name as LinkTypeName,
    pl.RelatedPostId
from 
    RecursiveUserActivity ua
left join 
    UserRecentBadges urt on urt.UserId = ua.UserId
left join 
    UserTagStats uts on uts.UserId = ua.UserId
left join 
    QuestionClosedInfo qc on qc.CloseVoterUserId = ua.UserId
left join 
    QuestionAnswerAggregates qaa on qaa.QuestionId = qc.QuestionId
left join 
    PostLinks pl on pl.PostId in (
        select p.Id from Posts p where p.OwnerUserId = ua.UserId
    )
left join
    LinkTypes lt on lt.Id = pl.LinkTypeId
where 
    ua.Reputation > 1000
order by 
    ua.Reputation desc,
    ua.LastAccessDate desc
limit 100;