-- {"query": "2326.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1889} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, 1 as Level, array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0

    union all

    select t.Id, t.TagName, t.Count, r.Level + 1, r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> any(r.Path)
    where t.IsModeratorOnly = 0 and t.Count < r.Count
), 

PostScores as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(vs.UpVotes, 0) as UpVotes,
        coalesce(vs.DownVotes, 0) as DownVotes,
        coalesce(bd.BadgeCount, 0) as BadgeCount,
        coalesce(pc.CommentCount, 0) as CommentCount,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed
    from Posts p
    left join (
        select PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) vs on vs.PostId = p.Id
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) bd on bd.UserId = p.OwnerUserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) pc on pc.PostId = p.Id
    where p.PostTypeId in (1,2)
),

RankedAnswers as (
    select 
        p2.Id as AnswerId,
        p2.ParentId,
        p2.Score,
        p2.ViewCount,
        p2.UpVotes,
        p2.DownVotes,
        p2.BadgeCount,
        p2.CommentCount,
        row_number() over (
            partition by p2.ParentId 
            order by (p2.UpVotes - p2.DownVotes) desc, p2.Score desc, p2.CreationDate asc
        ) as AnswerRank
    from PostScores p2
    where p2.PostTypeId = 2
),

UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        max(p.CreationDate) as LastPostDate,
        count(distinct c.Id) as CommentsMade,
        count(b.Id) as BadgesEarned,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        sum(coalesce(v.UpVotes,0) - coalesce(v.DownVotes,0)) as NetVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select PostId, sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes, sum(case when VoteTypeId=3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),

DuplicatesAndLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),

ClosedPostsWithReasons as (
    select 
        ph.PostId, 
        min(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),

PostsWithCloseReasons as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        cr.CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    left join ClosedPostsWithReasons cr on cr.PostId = p.Id
    left join CloseReasonTypes crt on crt.Id = cr.CloseReasonId
    where p.PostTypeId = 1
),

TopQuestionAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.AnswerId,
        a.ViewCount as AnswerViews,
        a.Score as AnswerScore,
        a.UpVotes as AnswerUpVotes,
        a.DownVotes as AnswerDownVotes,
        a.BadgeCount as AnswerOwnerBadgeCount,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc) as AnswerRank
    from PostsWithCloseReasons q
    join RankedAnswers a on a.ParentId = q.Id and a.AnswerRank = 1
    join Users u on u.Id = a.ParentId
    where q.CloseReasonId is null
),

FinalResult as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CloseReasonName,
        u.DisplayName as QuestionOwnerName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.BadgesEarned,
        ua.AvgPostScore,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerViews,
        a.AnswerUpVotes,
        a.AnswerDownVotes,
        a.AnswerOwnerBadgeCount,
        a.AnswerOwnerDisplayName,
        coalesce(dl.DuplicateCount, 0) as DuplicateLinksCount,
        coalesce(cm.CommentCount, 0) as CommentCount,
        case 
            when q.CloseReasonName is not null then 'Closed'
            else 'Open'
        end as PostStatus,
        row_number() over (partition by u.Id order by q.CreationDate desc) as UserQuestionRank
    from PostsWithCloseReasons q
    left join Users u on u.Id = q.OwnerUserId
    left join UserActivity ua on ua.UserId = u.Id
    left join TopQuestionAnswers a on a.QuestionId = q.Id
    left join (
        select PostId, count(*) as DuplicateCount
        from PostLinks 
        where LinkTypeId = 3
        group by PostId
    ) dl on dl.PostId = q.Id
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) cm on cm.PostId = q.Id
    where q.Score >= 5
)

select 
    fr.QuestionId,
    fr.Title,
    fr.QuestionOwnerName,
    fr.QuestionScore,
    fr.QuestionViews,
    fr.PostStatus,
    fr.CloseReasonName,
    fr.QuestionsPosted,
    fr.AnswersPosted,
    fr.BadgesEarned,
    round(fr.AvgPostScore::numeric, 2) as AvgPostScore,
    fr.AnswerId,
    fr.AnswerOwnerDisplayName,
    fr.AnswerScore,
    fr.AnswerViews,
    fr.AnswerUpVotes,
    fr.AnswerDownVotes,
    fr.AnswerOwnerBadgeCount,
    fr.DuplicateLinksCount,
    fr.CommentCount,
    fr.UserQuestionRank,
    concat(
        'Q:', fr.Title, 
        ' | Owner: ', fr.QuestionOwnerName, 
        ' | Score: ', fr.QuestionScore, 
        ' | Views: ', fr.QuestionViews,
        ' | Status: ', fr.PostStatus, 
        coalesce(concat(' (', fr.CloseReasonName, ')'), ''),
        ' | Top Answer Score: ', fr.AnswerScore,
        ' | Duplicate Links: ', fr.DuplicateLinksCount,
        ' | Comments: ', fr.CommentCount
    ) as Summary
from FinalResult fr
where fr.UserQuestionRank <= 3
order by fr.QuestionScore desc, fr.QuestionViews desc, fr.AnswerScore desc
limit 100;