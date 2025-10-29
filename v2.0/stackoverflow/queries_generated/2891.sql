-- {"query": "2891.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1476} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreation,
        ph.CreationDate as LastEditDate,
        row_number() over (partition by p.Id order by ph.CreationDate desc nulls last) as rn_edit
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.UserId = u.Id
    where p.PostTypeId in (1, 2)
),
FilteredUserActivity as (
    select
        UserId,
        DisplayName,
        Reputation,
        PostId,
        PostTypeId,
        PostCreation,
        LastEditDate
    from RecursiveUserActivity
    where rn_edit = 1

    union all

    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        null,
        null,
        null,
        null
    from Users u
    where not exists (
        select 1 from Posts p where p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    )
),
AggregatedBadges as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId, b.Class) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn_badge
    from Badges b
    where b.Date >= current_date - interval '365 days'
),
UserPopularPosts as (
    select
        p.OwnerUserId as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.FavoriteCount,
        rank() over (partition by p.OwnerUserId order by coalesce(p.FavoriteCount,0) desc, p.Score desc, p.CreationDate desc) as fav_rank
    from Posts p
    where p.PostTypeId = 1 and p.FavoriteCount > 0
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AnswerCount > 0
),
TopCommenters as (
    select
        c.UserId,
        u.DisplayName,
        count(*) as CommentCount,
        sum(c.Score) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    inner join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
    having count(*) > 10
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        crt.Name as CloseReason,
        ph.CreationDate as ClosedDate
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    inner join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 and p.PostTypeId = 1
),
FinalResult as (
    select
        fua.UserId,
        fua.DisplayName,
        fua.Reputation,
        max(fua.LastEditDate) as LastEditDate,
        max(ab.BadgeName) filter (where ab.Class = 1) as TopGoldBadge,
        max(ab.BadgeCount) filter (where ab.Class = 1) as GoldBadgeCount,
        (select count(*) from UserPopularPosts upp where upp.UserId = fua.UserId and upp.fav_rank = 1) as TopFavoritedQuestions,
        coalesce(tc.CommentCount, 0) as TotalComments,
        coalesce(sum(qwa.AnswerScore), 0) as SumAnswerScores,
        count(distinct cqwr.PostId) as CountClosedQuestions,
        string_agg(distinct cqwr.CloseReason, ', ') as CloseReasons
    from FilteredUserActivity fua
    left join AggregatedBadges ab on ab.UserId = fua.UserId and ab.rn_badge = 1
    left join QuestionsWithAnswers qwa on qwa.AnswerOwnerUserId = fua.UserId
    left join TopCommenters tc on tc.UserId = fua.UserId
    left join ClosedQuestionsWithReasons cqwr on cqwr.PostId in (
        select p.Id from Posts p where p.OwnerUserId = fua.UserId and p.PostTypeId = 1
    )
    group by fua.UserId, fua.DisplayName, fua.Reputation, tc.CommentCount
    having (GoldBadgeCount is null or GoldBadgeCount < 5) or (SumAnswerScores > 100)
    order by SumAnswerScores desc nulls last, GoldBadgeCount desc nulls last
    limit 100
)
select
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.LastEditDate,
    fr.TopGoldBadge,
    fr.GoldBadgeCount,
    fr.TopFavoritedQuestions,
    fr.TotalComments,
    fr.SumAnswerScores,
    fr.CountClosedQuestions,
    coalesce(fr.CloseReasons, 'None') as CloseReasons,
    case 
        when fr.Reputation > 10000 then 'High Rep'
        when fr.Reputation between 1000 and 10000 then 'Medium Rep'
        else 'Low Rep' 
    end as ReputationCategory,
    length(coalesce(u.AboutMe, '')) as AboutMeLength,
    strpos(lower(coalesce(u.AboutMe, '')), 'sql') > 0 as HasSQLInAboutMe
from FinalResult fr
left join Users u on u.Id = fr.UserId
where coalesce(fr.TotalComments, 0) > 0
union
select
    u.Id,
    u.DisplayName,
    u.Reputation,
    null,
    null,
    null,
    0,
    0,
    0,
    0,
    'None' as CloseReasons,
    case 
        when u.Reputation > 10000 then 'High Rep'
        when u.Reputation between 1000 and 10000 then 'Medium Rep'
        else 'Low Rep' 
    end,
    length(coalesce(u.AboutMe, '')),
    strpos(lower(coalesce(u.AboutMe, '')), 'sql') > 0
from Users u
where not exists (select 1 from FilteredUserActivity fua where fua.UserId = u.Id)
order by ReputationCategory desc, Reputation desc, DisplayName
limit 200;