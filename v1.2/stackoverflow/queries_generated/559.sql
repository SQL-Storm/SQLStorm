-- {"query": "559.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1658} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1 as Level,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(b.Class), 0) as BadgeScore,
        row_number() over (order by count(b.Id) desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        count(a.Id) as TotalAnswers,
        max(a.Score) filter (where a.Id is not null) as MaxAnswerScore,
        avg(a.Score) filter (where a.Id is not null) as AvgAnswerScore,
        sum(case when a.OwnerUserId = p.OwnerUserId then 1 else 0 end) as AnswersByQuestionOwner
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
PostCommentStats as (
    select
        p.Id as PostId,
        count(c.Id) as CommentCount,
        sum(c.Score) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pq.Title as DuplicateTitle,
        po.Title as OriginalTitle
    from PostLinks pl
    join Posts pq on pq.Id = pl.PostId and pq.PostTypeId = 1
    join Posts po on po.Id = pl.RelatedPostId and po.PostTypeId = 1
    where pl.LinkTypeId = 3
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId,
        max(ph.CreationDate) as CloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
TopTags as (
    select
        tag,
        count(*) as QuestionsCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViewCount
    from Posts p,
    unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as tag
    where p.PostTypeId = 1
    group by tag
    order by QuestionsCount desc
    limit 10
)

select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.EmailHash,
    u.AccountId,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    ubs.BadgeScore,
    ubs.BadgeRank,
    pas.QuestionId,
    pas.Title as QuestionTitle,
    pas.QuestionScore,
    pas.ViewCount as QuestionViewCount,
    pas.TotalAnswers,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.AnswersByQuestionOwner,
    pcs.CommentCount as PostCommentCount,
    pcs.TotalCommentScore,
    pcs.LastCommentDate,
    da.DuplicateQuestionId,
    da.OriginalQuestionId,
    da.DuplicateTitle,
    da.OriginalTitle,
    qci.CloseReasonId,
    qci.CloseDate,
    qci.ReopenDate,
    tt.tag as TopTag,
    tt.QuestionsCount as TopTagQuestionsCount,
    tt.AvgScore as TopTagAvgScore,
    tt.MaxViewCount as TopTagMaxViewCount,
    rth.Level as TagHierarchyLevel,
    array_to_string(rth.Path, ' > ') as TagHierarchyPath,
    uaw.CumulativeQuestions,
    uaw.CumulativeAnswers,
    uaw.CumulativePostScore,
    length(coalesce(u.AboutMe, '')) as AboutMeLength,
    case when u.AboutMe is null then 'No AboutMe' else 'Has AboutMe' end as AboutMeStatus,
    case when u.WebsiteUrl is not null and u.WebsiteUrl like 'https%' then 'Secure Website' else 'Non-secure or No Website' end as WebsiteSecurityStatus
from Users u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join PostAnswerStats pas on pas.OwnerUserId = u.Id
left join PostCommentStats pcs on pcs.PostId = pas.QuestionId
left join DuplicateQuestions da on da.DuplicateQuestionId = pas.QuestionId
left join QuestionCloseInfo qci on qci.PostId = pas.QuestionId
left join TopTags tt on tt.tag = any(string_to_array(substring(pas.Tags from 2 for length(pas.Tags) - 2), '><'))
left join RecursiveTagHierarchy rth on rth.TagName = tt.tag
left join UserActivityWindow uaw on uaw.Id = u.Id
where u.Reputation > 1000
  and pas.QuestionScore > 5
  and (qci.CloseDate is null or qci.ReopenDate is not null)
  and (u.Views > 100 or u.UpVotes > 10)
order by ubs.BadgeRank, pas.QuestionScore desc
limit 100;