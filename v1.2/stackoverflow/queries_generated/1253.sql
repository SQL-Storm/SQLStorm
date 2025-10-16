-- {"query": "1253.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1520} 
with RecursiveTagStats as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.ViewCount,0) as TagPostViews,
        coalesce(p.Score,0) as TagPostScore,
        array[]::int[] as AncestorTagIds
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        r.Id,
        r.TagName,
        r.Count,
        r.TagPostViews,
        r.TagPostScore,
        rt.AncestorTagIds || r.Id
    from RecursiveTagStats rt
    join Tags r on r.Id != all(rt.AncestorTagIds)
    where r.Count < rt.Count
)
,
UserPostAggregates as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        sum(coalesce(p.ViewCount,0)) as TotalPostViews,
        avg(coalesce(p.Score,0)) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(b.Class = 1)::int as GoldBadges,
        sum(b.Class = 2)::int as SilverBadges,
        sum(b.Class = 3)::int as BronzeBadges,
        rank() over (order by sum(coalesce(p.Score,0)) desc nulls last) as UserRankByScore,
        row_number() over (partition by u.Location order by sum(coalesce(p.Score,0)) desc nulls last) as RankInLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Location
)
,
TopQuestionWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreated,
        q.Score as QuestionScore,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreated,
        u.DisplayName as AnswerUser,
        u.Reputation,
        dense_rank() over (partition by q.Id order by a.Score desc nulls last) as AnswerRankByScore,
        count(distinct c.Id) as CommentsOnAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    left join Comments c on c.PostId = a.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.Score, a.Id, a.Score, a.CreationDate, u.DisplayName, u.Reputation
)
,
FilteredLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.CreationDate >= '2023-01-01' and lt.Name in ('Duplicate','Linked')
)
,
ComplexBadgeLogic as (
    select
        b.UserId,
        case 
            when b.TagBased = 1 and b.Class = 1 then 'GoldTagBadge'
            when b.TagBased = 1 and b.Class = 2 then 'SilverTagBadge'
            when b.TagBased = 1 and b.Class = 3 then 'BronzeTagBadge'
            when b.TagBased = 0 and b.Class = 1 then 'GoldNamedBadge'
            when b.TagBased = 0 and b.Class = 2 then 'SilverNamedBadge'
            when b.TagBased = 0 and b.Class = 3 then 'BronzeNamedBadge'
            else 'Other'
        end as BadgeCategory,
        count(*) over (partition by b.UserId) as TotalBadges
    from Badges b
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Location,
    upa.TotalQuestions,
    upa.TotalAnswers,
    upa.TotalPostScore,
    upa.TotalPostViews,
    upa.AvgPostScore,
    upa.GoldBadges,
    upa.SilverBadges,
    upa.BronzeBadges,
    upa.UserRankByScore,
    upa.RankInLocation,
    t.QuestionId,
    t.Title as QuestionTitle,
    t.Tags as QuestionTags,
    t.QuestionCreated,
    t.QuestionScore,
    t.AnswerId,
    t.AnswerScore,
    t.AnswerCreated,
    t.AnswerUser,
    t.Reputation as AnswerUserReputation,
    t.CommentsOnAnswer,
    fl.LinkTypeName,
    cbl.BadgeCategory,
    cbl.TotalBadges,
    coalesce((
        select count(*) from Comments c2
        where c2.PostId = t.QuestionId
        and c2.CreationDate > t.QuestionCreated
        and c2.Text ilike '%performance%'
    ),0) as CommentsMentioningPerformanceCount,
    (case 
        when strpos(t.Tags, '<sql>') > 0 then 1 else 0
     end) as HasSQLTag,
    (case 
        when u.Reputation > 50000 or upa.UserRankByScore <= 50 then true else false 
     end) as IsTopUser,
    -- Window function over user badge count
    count(b.Id) over (partition by b.UserId) as UserBadgeCountWindow,
    -- A complicated string concat with null logic
    concat_ws(' | ', nullif(u.DisplayName,''), coalesce(u.Location,'<no location>'), coalesce(substr(u.WebsiteUrl,1,30),'<no url>')) as UserDisplaySummary
from Users u
left join UserPostAggregates upa on upa.UserId = u.Id
left join TopQuestionWithAnswers t on t.AnswerUser = u.DisplayName and t.AnswerScore > 10
left join FilteredLinks fl on fl.PostId = t.QuestionId
left join Badges b on b.UserId = u.Id
left join ComplexBadgeLogic cbl on cbl.UserId = u.Id
where u.CreationDate > '2015-01-01'
and (upa.TotalPostScore > 100 or upa.UserRankByScore <= 100)
and (t.AnswerCreated between (u.CreationDate) and now() or t.AnswerCreated is null)
order by upa.TotalPostScore desc nulls last, upa.TotalAnswers desc nulls last
limit 100;