-- {"query": "1179.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1199} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId, 
        u.DisplayName, 
        b.Name as BadgeName, 
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class asc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
), TopBadges as (
    select UserId, DisplayName, BadgeName, Class 
    from RecursiveUserBadges 
    where BadgeRank <= 3
), PostScoreStats as (
    select 
        p.OwnerUserId, 
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        sum(case when p.Score > 10 then 1 else 0 end) as HighScorePosts,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore
    from Posts p
    where p.OwnerUserId is not null and p.PostTypeId in (1, 2)
    group by p.OwnerUserId
), UserRecentActivity as (
    select 
        u.Id,
        max(coalesce(p.LastActivityDate, u.LastAccessDate)) as RecentActivity,
        (select count(*) from Comments c where c.UserId = u.Id and c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as RecentComments,
        (select count(*) from Votes v where v.UserId = u.Id and v.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as RecentVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
), QuestionsWithAnswerLead as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.ViewCount,
        q.Score as QuestionScore,
        q.CreationDate,
        ans.Id as AcceptedAnswerId,
        ans.Score as AcceptedAnswerScore,
        ans.OwnerUserId as AnswerOwnerUserId,
        ans.Body,
        coalesce(ans.Score, 0) - coalesce(q.Score, 0) as ScoreDifference,
        row_number() over (partition by q.Id order by ans.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts ans on ans.ParentId = q.Id and ans.PostTypeId = 2
    where q.PostTypeId = 1
), DuplicateDuplicates as (
    -- Find duplicates and their original questions along with close reasons if any
    select 
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        crt.Name as CloseReason,
        ph.Comment as CloseReasonId
    from PostLinks pl
    left join Posts p on pl.PostId = p.Id
    left join PostHistory ph on ph.PostId = pl.PostId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::int = cast(ph.Comment as int)
    where pl.LinkTypeId = 3
), UserActivityRankings as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        us.PostCount,
        us.AvgScore,
        us.HighScorePosts,
        ria.RecentActivity,
        ria.RecentComments,
        ria.RecentVotes,
        case 
            when u.Reputation > 100000 then 'Legendary' 
            when u.Reputation > 20000 then 'High' 
            when u.Reputation > 5000 then 'Medium' 
            else 'Low' 
        end as ReputationClass
    from Users u
    left join PostScoreStats us on u.Id = us.OwnerUserId
    left join UserRecentActivity ria on u.Id = ria.Id
)
select distinct
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    uar.ReputationClass,
    uar.PostCount,
    uar.AvgScore,
    uar.HighScorePosts,
    uar.RecentActivity,
    uar.RecentComments,
    uar.RecentVotes,
    tb.BadgeName,
    tb.Class as BadgeClass,
    qle.QuestionId,
    qle.Title as QuestionTitle,
    qle.ViewCount,
    qle.QuestionScore,
    qle.AcceptedAnswerId,
    qle.AcceptedAnswerScore,
    qle.ScoreDifference,
    dd.DuplicatePostId,
    dd.OriginalPostId,
    dd.CloseReason,
    case 
        when qle.ScoreDifference is null then 'No Answer Yet' 
        when qle.ScoreDifference > 5 then 'Answer Score Much Higher' 
        when qle.ScoreDifference between -5 and 5 then 'Scores Similar' 
        else 'Question Score Higher' 
    end as ScoreComparisonCategory,
    substring(coalesce(qle.Body, '') from 1 for 100) || '...' as AnswerBodyPreview,
    coalesce(uar.DisplayName, 'Anonymous') || ' (' || coalesce(cast(uar.Reputation as varchar), 'N/A') || ')' as UserDisplayWithReputation
from UserActivityRankings uar
left join TopBadges tb on uar.UserId = tb.UserId
left join QuestionsWithAnswerLead qle on qle.AnswerOwnerUserId = uar.UserId and qle.AnswerRank = 1
left join DuplicateDuplicates dd on dd.DuplicatePostId = qle.QuestionId
where uar.PostCount > 10 and (uar.RecentComments > 5 or uar.RecentVotes > 5)
order by uar.Reputation desc, uar.PostCount desc, tb.Class asc nulls last, qle.ViewCount desc
limit 100;