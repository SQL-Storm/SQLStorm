-- {"query": "1013.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1183} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, b.Class
),
PostAnswerDetails as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score as AnswerScore,
        p.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswererName,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2
),
TopAnswersWithQuestion as (
    select
        pa.AnswerId,
        pa.QuestionId,
        pa.AnswerScore,
        pa.AnswerCreationDate,
        pa.AnswererName,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        q.ViewCount as QuestionViewCount,
        q.Score as QuestionScore,
        u.DisplayName as QuestionOwnerName,
        u.Reputation as QuestionOwnerRep
    from PostAnswerDetails pa
    join Posts q on pa.QuestionId = q.Id and q.PostTypeId = 1
    left join Users u on q.OwnerUserId = u.Id
    where pa.AnswerRank <= 3
),
FilteredComments as (
    select
        c.Id,
        c.PostId,
        c.Score as CommentScore,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        coalesce(u.DisplayName, c.UserDisplayName) as CommenterName,
        c.UserId
    from Comments c
    left join Users u on c.UserId = u.Id
    where c.Score >= 2
),
DuplicateLinkInfo as (
    select
        pl.PostId,
        count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateCount,
        max(pl.CreationDate) as LastDuplicateLinkDate
    from PostLinks pl
    group by pl.PostId
),
PostHistoryCloseCounts as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotesCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVotesCount
    from PostHistory ph
    group by ph.PostId
),
FinalSelection as (
    select
        t.AnswerId,
        t.QuestionId,
        t.AnswerScore,
        t.AnswerCreationDate,
        t.AnswererName,
        t.QuestionTitle,
        t.QuestionTags,
        t.QuestionViewCount,
        t.QuestionScore,
        t.QuestionOwnerName,
        t.QuestionOwnerRep,
        r.BadgeCount,
        r.Class as BadgeClass,
        d.DuplicateCount,
        d.LastDuplicateLinkDate,
        phc.CloseVotesCount,
        phc.ReopenVotesCount,
        fc.CommentScore,
        fc.CommentText,
        fc.CommentDate,
        fc.CommenterName,
        row_number() over (partition by t.QuestionId order by t.AnswerScore desc) as AnswerPositionWithinQuestion
    from TopAnswersWithQuestion t
    left join RecursiveUserBadgeCounts r on r.UserId = (select OwnerUserId from Posts where Id = t.AnswerId)
    left join DuplicateLinkInfo d on d.PostId = t.QuestionId
    left join PostHistoryCloseCounts phc on phc.PostId = t.QuestionId
    left join LATERAL (
        select * from FilteredComments fc2
        where fc2.PostId = t.AnswerId
        order by fc2.CommentScore desc, fc2.CommentDate asc 
        limit 1
    ) fc on true
)
select
    QuestionId,
    QuestionTitle,
    QuestionTags,
    QuestionViewCount,
    QuestionScore,
    QuestionOwnerName,
    QuestionOwnerRep,
    AnswerId,
    AnswerScore,
    AnswerCreationDate,
    AnswererName,
    BadgeCount,
    case BadgeClass
        when 1 then 'Gold'
        when 2 then 'Silver'
        when 3 then 'Bronze'
        else 'None'
    end as BadgeClassName,
    COALESCE(DuplicateCount,0) as DuplicateCount,
    LastDuplicateLinkDate,
    COALESCE(CloseVotesCount,0) as CloseVotesCount,
    COALESCE(ReopenVotesCount,0) as ReopenVotesCount,
    CommentScore,
    CommentText,
    CommentDate,
    CommenterName,
    AnswerPositionWithinQuestion,
    -- Complex calculated score combining multiple factors, with null-safe coalesce
    (AnswerScore * pow(1.05, COALESCE(BadgeCount,0))) +
    (COALESCE(CommentScore, 0) * 2) +
    (case when CloseVotesCount > 0 then -10 else 0 end) +
    (case when ReopenVotesCount > CloseVotesCount then 5 else 0 end) +
    (log(GREATEST(1, QuestionViewCount)) * 1.5) as CompositePopularityScore
from FinalSelection
where AnswerPositionWithinQuestion <= 2
  and (QuestionTags ilike '%<sql>%'
       or QuestionTags ilike '%<database>%'
       or QuestionTags ilike '%<performance>%')
order by CompositePopularityScore desc, AnswerCreationDate asc
limit 100;