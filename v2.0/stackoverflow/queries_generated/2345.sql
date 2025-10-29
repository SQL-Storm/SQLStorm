-- {"query": "2345.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1262} 
with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc, p.Score desc) as UserPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
RankedAnswers as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
TopAnswersWithQuestion as (
    select
        a.AnswerId,
        a.QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        q.Score as QuestionScore,
        q.CreationDate as QuestionCreationDate
    from RankedAnswers a
    inner join Posts q on q.Id = a.QuestionId and q.PostTypeId = 1
    where a.AnswerRank = 1
),
UserBadgeSummary as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Name, b.Class
),
ClosedQuestionHistory as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
UsersLatestComment as (
    select distinct on (c.UserId)
        c.UserId,
        c.Text as LatestComment,
        c.CreationDate as CommentDate
    from Comments c
    where c.UserId is not null
    order by c.UserId, c.CreationDate desc
),
PopularTags as (
    select TagName, Count 
    from Tags 
    where Count > 5000
),
QuestionsWithHighVotesOrViews as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        coalesce(clqh.CloseDate, timestamp 'epoch') as ClosedDateEpoch,
        (select count(*) 
            from Votes v 
            where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotesCount,
        (select count(*) 
            from Votes v 
            where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotesCount        
    from Posts p
    left join ClosedQuestionHistory clqh on clqh.PostId = p.Id
    where p.PostTypeId = 1
      and (p.Score > 100 or p.ViewCount > 50000)
      and coalesce(clqh.CloseDate, null) is null
),
CombinedUsersWithPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        rup.PostId,
        rup.PostTypeId,
        rup.Score as UserPostScore,
        rup.CreationDate as PostCreationDate,
        uws.LatestComment,
        uws.CommentDate,
        coalesce(ub.BadgeCount, 0) as TotalBadges
    from Users u
    left join RecursiveUserPosts rup on rup.UserId = u.Id and rup.UserPostRank = 1
    left join UsersLatestComment uws on uws.UserId = u.Id
    left join (
        select UserId, sum(BadgeCount) as BadgeCount
        from UserBadgeSummary
        group by UserId
    ) ub on ub.UserId = u.Id
    where u.Reputation > 500
)
select distinct
    cup.UserId,
    cup.DisplayName,
    cup.Reputation,
    cup.PostId,
    pt.Name as PostTypeName,
    cup.UserPostScore,
    cup.PostCreationDate,
    cup.LatestComment,
    cup.CommentDate,
    cup.TotalBadges,
    qhv.Title as PopularQuestionTitle,
    qhv.Score as PopularQuestionScore,
    qhv.ViewCount as PopularQuestionViews,
    string_agg(distinct pt2.Name, ',') filter (where pt2.Name is not null) over (partition by cup.UserId) as AllPostTypes,
    case 
        when cup.LatestComment is null then 'No recent comments'
        when length(cup.LatestComment) > 100 then substring(cup.LatestComment from 1 for 100) || '...'
        else cup.LatestComment
    end as CommentPreview,
    coalesce(clqh.CloseReasonName, 'Open') as LatestCloseReason,
    array_to_string(
        array(
            select ptags.TagName 
            from PopularTags ptags 
            where cstring_to_array(replace(replace(qhv.Tags, '><', ','), '<', ''), '>')::text[] @> array[ptags.TagName]
        ), ', '
    ) as PopularTagsInQuestion
from CombinedUsersWithPosts cup
inner join PostTypes pt on pt.Id = cup.PostTypeId
left join QuestionsWithHighVotesOrViews qhv on qhv.OwnerUserId = cup.UserId
left join PostTypes pt2 on pt2.Id = cup.PostTypeId
left join ClosedQuestionHistory clqh on clqh.PostId = cup.PostId
where cup.PostId is not null
order by cup.Reputation desc, cup.UserPostScore desc
limit 100;