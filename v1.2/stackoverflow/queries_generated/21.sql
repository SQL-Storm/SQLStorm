-- {"query": "21.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1407} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsers as (
    select * from RecursiveUserActivity where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.LastActivityDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        -- Extract first tag from Tags string, which is in format '<tag1><tag2><tag3>'
        substring(p.Tags from '<([^>]+)>') as FirstTag
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.Score > 0 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PositiveScorePostsLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
CorrelatedTopAnswer as (
    select
        q.Id as QuestionId,
        (select a.Id from Posts a where a.ParentId = q.Id order by a.Score desc limit 1) as TopAnswerId,
        (select a.Score from Posts a where a.ParentId = q.Id order by a.Score desc limit 1) as TopAnswerScore
    from Posts q
    where q.PostTypeId = 1
),
FinalResult as (
    select
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.CommentCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        pd.Id as PostId,
        pd.PostTypeName,
        pd.Title,
        pd.Score,
        pd.ViewCount,
        pd.IsClosed,
        acr.CloseReasonName,
        ans.TotalAnswers,
        ans.AvgAnswerScore,
        ans.MaxAnswerScore,
        ans.MinAnswerScore,
        cli.LinkTypeName,
        ua.PostsLast30Days,
        ua.PositiveScorePostsLast30Days,
        cta.TopAnswerId,
        cta.TopAnswerScore,
        -- Complex string expression: concatenate user display name with post title and first tag, handling nulls
        coalesce(tu.DisplayName, 'Anonymous') || ' - ' || coalesce(pd.Title, '[No Title]') || ' [' || coalesce(pd.FirstTag, 'NoTag') || ']' as UserPostSummary
    from TopUsers tu
    left join UserBadgeSummary ub on ub.UserId = tu.UserId
    left join PostDetails pd on pd.OwnerUserId = tu.UserId
    left join QuestionCloseReasons acr on acr.PostId = pd.Id
    left join AnswerStats ans on ans.QuestionId = pd.Id
    left join PostLinkInfo cli on cli.PostId = pd.Id
    left join UserActivityWindow ua on ua.UserId = tu.UserId and ua.PostId = pd.Id
    left join CorrelatedTopAnswer cta on cta.QuestionId = pd.Id
    where pd.PostTypeId = 1
)
select *
from FinalResult
where (Score > 5 or ViewCount > 1000 or GoldBadges > 0)
  and (IsClosed = 0 or CloseReasonName is null)
order by Reputation desc, Score desc, ViewCount desc
limit 50;