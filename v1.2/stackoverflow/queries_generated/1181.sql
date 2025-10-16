-- {"query": "1181.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1744} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(t.Count, 0) as TotalCount,
        ts.Id as ParentTagId,
        1 as Level
    from Tags t
    left join Tags ts on ts.TagName = substring(t.TagName, 1, char_length(t.TagName) - 1) -- example dummy self join for recursion
    where ts.Id is not null
    union all
    select
        r.TagId,
        r.TagName,
        r.TotalCount + coalesce(t.Count, 0),
        t.Id,
        r.Level + 1
    from RecursiveTagCounts r
    join Tags t on t.Id = r.ParentTagId
    where r.Level < 3
),
UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostCount,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        sum(b.Class) as BadgeClassSum,
        coalesce(sum(v.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(v.DownVotes), 0) as TotalDownVotes,
        count(distinct c.Id) as CommentCount,
        max(p.Score) over (partition by u.Id) as MaxPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LatestPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVotesAggregate as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVoteCount,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVoteCount,
        count(v.Id) filter (where v.VoteTypeId in (8,9)) as BountyCount,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as TotalBountyAmount,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextScore
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.Score, p.CreationDate, p.OwnerUserId
),
PopularQuestionsWithAnswers AS (
    select
        pq.Id as QuestionId,
        pq.Title,
        pq.Tags,
        pq.CreationDate as QuestionCreationDate,
        pq.Score as QuestionScore,
        pa.Id as AnswerId,
        pa.Score as AnswerScore,
        pa.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwner,
        r.TotalCount as TagTotalCount,
        case when pa.Score > pq.Score then 1 else 0 end as AnswerScoreHigherThanQuestion
    from Posts pq
    left join Posts pa on pa.ParentId = pq.Id and pa.PostTypeId = 2
    left join Users u on pa.OwnerUserId = u.Id
    left join RecursiveTagCounts r on strpos(pq.Tags, concat('<', r.TagName, '>')) > 0
    where pq.PostTypeId = 1
      and pq.Score > 100
      and pa.Score is not null
),
ClosedQuestionsWithReasons AS (
    select
        ph.PostId,
        p.Title,
        min(ph.CreationDate) as ClosedAt,
        max(case when ph.PostHistoryTypeId = 10 then cast(coalesce(ph.Comment, '') as varchar) else null end) as CloseReasonCode,
        crt.Name as CloseReasonName,
        u.DisplayName as CloserUser
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    group by ph.PostId, p.Title, crt.Name, u.DisplayName
),
RecentActivity AS (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        u.DisplayName as OwnerDisplayName,
        ph.LatestEditDate,
        ph.EditCount,
        sum(v.VoteCount) as TotalVotes
    from Posts p
    left join (
        select PostId,
            max(CreationDate) as LatestEditDate,
            count(*) as EditCount
        from PostHistory
        where PostHistoryTypeId in (4,5,6) -- edits of title, body, tags
        group by PostId
    ) ph on ph.PostId = p.Id
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select PostId,
            count(*) as VoteCount
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId in (1,2)
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.LastActivityDate, p.Score, u.DisplayName, ph.LatestEditDate, ph.EditCount
)
select
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeClassSum,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.CommentCount,
    ua.MaxPostScore,
    avg(pva.UpVoteCount) as AvgUpVotesPerPost,
    avg(pva.DownVoteCount) as AvgDownVotesPerPost,
    max(pva.TotalBountyAmount) as MaxBountyEarned,
    count(distinct pq.QuestionId) filter (where pq.AnswerScoreHigherThanQuestion = 1) as AnswersOutscoringQuestions,
    array_agg(distinct ct.CloseReasonName) filter (where ct.PostId is not null) as CloseReasonsEncountered,
    max(ra.EditCount) as MaxEditsOnPosts,
    min(ra.LatestEditDate) filter (where ra.LatestEditDate is not null) as EarliestRecentEdit,
    (select count(distinct CommenterId)
        from (
            select c.UserId as CommenterId
            from Comments c
            join Posts p2 on c.PostId = p2.Id
            where p2.OwnerUserId = ua.UserId
              and c.CreationDate > p2.CreationDate
              and c.Text ilike '%thank you%'
            limit 100
        ) sub
    ) as ThankYouCommentersCount,
    string_agg(distinct coalesce(ra.OwnerDisplayName, 'N/A'), ', ') filter (where ra.PostTypeId = 1) as ActiveQuestionOwners
from UserActivity ua
left join PostVotesAggregate pva on pva.OwnerUserId = ua.UserId
left join PopularQuestionsWithAnswers pq on pq.AnswerOwner = ua.DisplayName
left join ClosedQuestionsWithReasons ct on ct.PostId in (select Id from Posts where OwnerUserId = ua.UserId)
left join RecentActivity ra on ra.OwnerDisplayName = ua.DisplayName
group by
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeClassSum,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.CommentCount,
    ua.MaxPostScore
having count(distinct pq.QuestionId) > 5
order by ua.PostCount desc, ua.TotalUpVotes desc
limit 100;