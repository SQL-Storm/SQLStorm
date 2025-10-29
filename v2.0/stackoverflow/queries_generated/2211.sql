-- {"query": "2211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1479} 
with RecursiveTagHierarchy as (
    select 
        t.Id, 
        t.TagName, 
        t.Count,
        coalesce(p.ViewCount,0) as ViewCount,
        p.OwnerUserId,
        1 as Level
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        coalesce(p2.ViewCount,0),
        p2.OwnerUserId,
        r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.WikiPostId = r.Id
    left join Posts p2 on p2.Id = t2.ExcerptPostId
    where r.Level < 3
),
PostVotesDetail as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(v.FavoriteVotes,0) as FavoriteVotes
    from Posts p
    left join (
        select 
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes,
            sum(case when VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostCommentSummary as (
    select 
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(left(nullif(c.Text,''),50), ' | ') as SampleComments
    from Comments c
    group by c.PostId
),
PostCloseReasons as (
    select distinct
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
    where ph.PostHistoryTypeId = 10
),
QuestionAnswerAnalysis as (
    select 
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwner,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        qa.Id as AnswerId,
        qa.OwnerUserId as AnswerOwner,
        qa.CreationDate as AnswerCreation,
        qa.Score as AnswerScore,
        row_number() over (partition by q.Id order by qa.Score desc, qa.CreationDate) as AnswerRank
    from Posts q
    left join Posts qa on qa.ParentId = q.Id and qa.PostTypeId = 2
    where q.PostTypeId = 1
),
TopContributors as (
    select 
        u.Id, 
        u.DisplayName,
        count(p.Id) as PostsCount,
        sum(p.Score) as TotalScore,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        rank() over (order by sum(p.Score) desc) as Ranking
    from Users u
    join Posts p on p.OwnerUserId = u.Id 
    group by u.Id, u.DisplayName
    having count(p.Id) > 50
    order by TotalScore desc
)
select 
    qaa.QuestionId,
    qaa.Title as QuestionTitle,
    qaa.QuestionOwner,
    ub.DisplayName as QuestionOwnerName,
    qaa.QuestionCreation,
    qaa.QuestionScore,
    qaa.QuestionViews,
    qaa.AnswerId,
    ausr.DisplayName as AnswerOwnerName,
    qaa.AnswerCreation,
    qaa.AnswerScore,
    qaa.AnswerRank,
    coalesce(pcs.CommentCount, 0) as QuestionCommentCount,
    coalesce(pcsa.CommentCount, 0) as AnswerCommentCount,
    coalesce(clr.CloseReasonName, 'Open') as CloseReason,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    tcs.PostsCount,
    tcs.TotalScore,
    'TopContributor' = case when tcs.Ranking <= 10 then 1 else 0 end,
    concat_ws(' | ', substring(qaa.Title from 1 for 30), 'by', ub.DisplayName, 'viewed', qaa.QuestionViews, 'times') as TitleSummary,
    length(qaa.Title) as TitleLength,
    case when qaa.QuestionScore < 0 then 'NegativeScore' else 'NonNegativeScore' end as ScoreCategory,
    nt.NullTagCount,
    rth.Level as TagHierarchyLevel,
    rth.TagName as TagNameSample
from QuestionAnswerAnalysis qaa
left join Users ub on ub.Id = qaa.QuestionOwner
left join Users ausr on ausr.Id = qaa.AnswerOwner
left join PostCommentSummary pcs on pcs.PostId = qaa.QuestionId
left join PostCommentSummary pcsa on pcsa.PostId = qaa.AnswerId
left join PostCloseReasons clr on clr.PostId = qaa.QuestionId
left join UserBadgeStats ubs on ubs.UserId = qaa.QuestionOwner
left join TopContributors tcs on tcs.Id = qaa.AnswerOwner
left join (
    select 
        p.Id as PostId, 
        coalesce(array_length(regexp_split_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '\><'), 1), 0) as NullTagCount
    from Posts p
    where p.PostTypeId = 1
) nt on nt.PostId = qaa.QuestionId
left join RecursiveTagHierarchy rth on rth.OwnerUserId = qaa.QuestionOwner
where qaa.AnswerRank = 1
and qaa.QuestionCreation > now() - interval '1 year'
order by qaa.QuestionScore desc, qaa.QuestionViews desc
limit 100;