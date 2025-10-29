-- {"query": "2905.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1417} 
with QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        array_agg(distinct pt.Name) filter (where pt.Name is not null) as PostHistoryTypesEdited,
        max(ph.CreationDate) as LastEditDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(distinct b.Id) filter (where b.Class = 1) as OwnerGoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as OwnerSilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as OwnerBronzeBadges,
        case 
            when p.ClosedDate is not null then 'Closed'
            else 'Open'
        end as PostState
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    left join PostHistoryTypes pt on ph.PostHistoryTypeId = pt.Id
    left join Votes v on v.PostId = p.Id
    left join Badges b on b.UserId = p.OwnerUserId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate, p.OwnerUserId, u.DisplayName, p.AnswerCount, p.ViewCount, p.Score, p.ClosedDate
), AnswerInfo as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.Body,
        a.LastActivityDate,
        u.DisplayName as AnswererName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
), TopAnswers as (
    select
        AnswerId,
        QuestionId,
        OwnerUserId,
        CreationDate,
        Score,
        Body,
        LastActivityDate,
        AnswererName,
        AnswerRank
    from AnswerInfo
    where AnswerRank <= 3
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        u.DisplayName as RelOwnerName,
        p.Score as RelScore,
        p.CreationDate as RelCreationDate
    from PostLinks pl
    join Posts p on pl.RelatedPostId = p.Id
    left join Users u on p.OwnerUserId = u.Id
    where pl.LinkTypeId = 3 -- Duplicate
), UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesEarned,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(distinct p.Id) > 10 or count(distinct c.Id) > 20
), QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
), RecursiveRelatedPosts (RootQuestionId, RelatedPostId, Depth) as (
    select p.Id, pl.RelatedPostId, 1
    from Posts p
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 1
    where p.PostTypeId = 1
    union all
    select rr.RootQuestionId, pl.RelatedPostId, rr.Depth + 1
    from RecursiveRelatedPosts rr
    join PostLinks pl on pl.PostId = rr.RelatedPostId and pl.LinkTypeId = 1
    where rr.Depth < 3
)
select 
    qs.QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.OwnerName,
    qs.AnswerCount,
    qs.ViewCount,
    qs.Score,
    qs.UpVotes,
    qs.DownVotes,
    qs.OwnerGoldBadges,
    qs.OwnerSilverBadges,
    qs.OwnerBronzeBadges,
    qs.PostState,
    coalesce(qcr.CloseReasonName, 'Not Closed') as CloseReason,
    ta.AnswerId,
    ta.Score as AnswerScore,
    ta.AnswererName,
    substring(regexp_replace(ta.Body, '<[^>]+>', '', 'g') from 1 for 100) as AnswerSnippet,
    ul.RelatedPostId as DuplicateOf,
    ul.RelOwnerName as DuplicateOwner,
    ur.UserId as TopUserId,
    ur.DisplayName as TopUserName,
    ur.Reputation,
    ur.QuestionsAsked,
    ur.AnswersGiven,
    ur.CommentsMade,
    ur.BadgesEarned,
    rr.Depth as RelatedDepth
from QuestionStats qs
left join QuestionCloseReasons qcr on qcr.PostId = qs.QuestionId
left join TopAnswers ta on ta.QuestionId = qs.QuestionId and ta.AnswerRank = 1
left join DuplicateLinks ul on ul.PostId = qs.QuestionId
left join UserActivity ur on ur.UserId = qs.OwnerUserId
left join RecursiveRelatedPosts rr on rr.RootQuestionId = qs.QuestionId
where qs.ViewCount > 1000
  and (qs.Score > 5 or qs.PostState = 'Closed')
  and (ta.AnswerScore is null or ta.AnswerScore > 0)
order by qs.ViewCount desc, qs.Score desc, ta.Score desc
limit 50;