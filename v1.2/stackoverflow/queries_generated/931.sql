-- {"query": "931.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1320} 

with RecursiveBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by u.Id order by count(*) desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class
),
QuestionsCTE as (
    select 
        p.Id, 
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        ph.PostHistoryTypeId,
        ph.CreationDate as PHCreationDate,
        ph.Text as PHText,
        ph.UserId as PHUserId,
        ph.Comment as PHComment,
        p.AcceptedAnswerId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10 -- Post Closed
    where p.PostTypeId = 1
),
AnswerRankings as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as ScoreRank,
        dense_rank() over (partition by a.ParentId order by a.OwnerUserId) as OwnerRank,
        count(*) over (partition by a.ParentId) as AnswerCount
    from Posts a
    where a.PostTypeId = 2
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        coalesce(u.Reputation,0) as Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct a.Id) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        max(p.CreationDate) as LastPostDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
DuplicatedQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        p1.CreationDate as DuplicateCreation,
        p2.CreationDate as OriginalCreation
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
QuestionWithBadges as (
    select
        q.Id as QuestionId,
        q.Title,
        q.ViewCount,
        q.Score,
        q.Tags,
        q.AcceptedAnswerId,
        badge_stats.Class,
        badge_stats.BadgeCount
    from QuestionsCTE q
    left join LATERAL (
        select
            b.Class,
            count(*) as BadgeCount
        from Badges b
        where b.UserId = q.OwnerUserId
        group by b.Class
        order by count(*) desc
        limit 1
    ) badge_stats on true
),
AnswersWithComments as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        count(c.Id) as CommentCount,
        string_agg(coalesce(c.Text, '') || ' (' || coalesce(c.UserDisplayName, 'anonymous') || ')', ' | ' order by c.CreationDate) as CommentsTexts
    from Posts a
    left join Comments c on c.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate
),
FinalOutput as (
    select distinct
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.BadgeCount,
        q.QuestionId,
        q.Title as QuestionTitle,
        q.ViewCount as QuestionViews,
        q.Score as QuestionScore,
        q.Tags,
        q.AcceptedAnswerId,
        q.Class as TopBadgeClass,
        q.BadgeCount as TopBadgeCount,
        a.AnswerId,
        a.AnswerScore,
        a.CommentCount as AnswerCommentCount,
        a.CommentsTexts,
        rank() over (partition by q.QuestionId order by a.AnswerScore desc nulls last) as AnswerRank,
        dq.DuplicateQuestionId,
        dq.OriginalQuestionId,
        dq.DuplicateTitle,
        dq.OriginalTitle
    from Users u
    left join UserActivity ua on ua.Id = u.Id
    left join QuestionWithBadges q on q.QuestionId in (
        select p.Id from Posts p where p.PostTypeId = 1 and p.OwnerUserId = u.Id
    )
    left join AnswersWithComments a on a.QuestionId = q.QuestionId
    left join DuplicatedQuestions dq on dq.DuplicateQuestionId = q.QuestionId
    where ua.QuestionCount > 5
)
select * from FinalOutput
where AnswerRank <= 3
   and (TopBadgeClass = 1 or TopBadgeClass is null)
order by Reputation desc, QuestionScore desc, AnswerScore desc
limit 100;
