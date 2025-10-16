-- {"query": "4100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1138} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName,
           b.Id as BadgeId, b.Name as BadgeName, b.Class,
           row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 5000
),
TopUserBadges as (
    select UserId, DisplayName, BadgeId, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        case
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        string_agg(distinct lt.Name, ', ') filter (where lt.Id is not null) as LinkedPostTypes,
        array_to_string(array_agg(distinct coalesce(pl2.LinkTypeId::text, 'None')), ',') as LinkTypeIds
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join PostLinks pl2 on p.Id = pl2.PostId
    where p.PostTypeId = 1  -- questions only
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.ClosedDate
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId in (select UserId from RecursiveUserBadges where Class = 1) then 1 else 0 end) as GoldAnswerers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionWithAnswers as (
    select q.*, coalesce(a.TotalAnswers, 0) as TotalAnswers,
                  coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
                  coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
                  coalesce(a.GoldAnswerers, 0) as GoldAnswerers
    from QuestionStats q
    left join AnswerStats a on q.QuestionId = a.QuestionId
),
RankedQuestions as (
    select *,
        row_number() over (partition by IsClosed order by Score desc, ViewCount desc) as rn
    from QuestionWithAnswers
),
ClosedQuestionsWithReasons as (
    select ph.PostId, crt.Name as CloseReason, max(ph.CreationDate) as LastClosedDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
)
select
    rq.rn,
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.CommentCount,
    rq.FavoriteCount,
    rq.UpVotes,
    rq.DownVotes,
    rq.IsClosed,
    cr.CloseReason,
    cr.LastClosedDate,
    rq.TotalAnswers,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.GoldAnswerers,
    tu.BadgeName as TopBadge,
    substring(rq.Tags from '%#"%#"%' for '#"%' ) as ExampleTagFragment,
    length(coalesce(rq.Title, '')) as TitleLength,
    case when rq.ViewCount > 10000 then 'Popular' else 'Normal' end as PopularityCategory,
    concat_ws(' | ', array_to_string(string_to_array(rq.Tags, '><'), ','), coalesce(rq.LinkedPostTypes, 'No Links')) as TagsAndLinks,
    case when rq.Score = 0 and rq.AnswerCount = 0 then null else (rq.Score::float / nullif(rq.AnswerCount,0)) end as ScorePerAnswerRatio,
    (select max(Score) from Posts p2 where p2.OwnerUserId = rq.OwnerUserId and p2.PostTypeId = 1) as MaxOwnerQuestionScore
from RankedQuestions rq
left join Users u on rq.OwnerUserId = u.Id
left join ClosedQuestionsWithReasons cr on rq.QuestionId = cr.PostId
left join TopUserBadges tu on rq.OwnerUserId = tu.UserId and tu.Class = 1
where rq.rn <= 50
order by rq.IsClosed, rq.Score desc, rq.ViewCount desc;