-- {"query": "814.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1426} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsRequired = 1
    union all
    select
        child.Id,
        child.TagName,
        child.Count,
        r.Level + 1,
        r.Path || child.TagName
    from Tags child
    join RecursiveTagHierarchy r on child.Id = r.Id + 1 and child.TagName <> all(r.Path)
    where r.Level < 3
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoresWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RecencyRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        count(*) over (partition by pl.PostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
),
CloseVotesCount as (
    select
        ph.PostId,
        count(*) as CloseVotes
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
FinalQuery as (
    select
        u.Id as UserId,
        coalesce(u.DisplayName,'<anon>') as UserName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        max(case when p.ScoreRank <= 5 then p.Score else null end) as Top5PostScore,
        avg(case when p.RecencyRank <= 100 then p.ViewCount else null end) as AvgViewsRecent100Posts,
        count(distinct case when dq.DuplicateCount > 1 then dq.PostId end) as UserDuplicatesPosts,
        sum(cv.CloseVotes) filter (where cv.CloseVotes > 0) as TotalCloseVotesOnUserPosts,
        string_agg(distinct substring(tags_tag.TagName from 1 for 10), ',' order by tags_tag.TagName) as UserTagSamples,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseVoteDate,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as FirstReopenVoteDate
    from Users u
    left join UserBadgeSummary ub on ub.UserId = u.Id
    left join PostScoresWindow p on p.OwnerUserId = u.Id
    left join DuplicateLinks dq on dq.PostId = p.Id
    left join CloseVotesCount cv on cv.PostId = p.Id
    left join Posts p2 on p2.OwnerUserId = u.Id and p2.PostTypeId = 1
    left join lateral (
        select unnest(string_to_array(coalesce(p2.Tags,''), '><')) as TagName
    ) tags_tag on true
    left join PostHistory ph on ph.PostId = p2.Id and ph.PostHistoryTypeId in (10,11)
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate, ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
    having count(p.Id) > 10 and avg(p.Score) > 0
)
select
    fq.UserId,
    fq.UserName,
    fq.Reputation,
    fq.TotalBadges,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.Top5PostScore,
    fq.AvgViewsRecent100Posts,
    fq.UserDuplicatesPosts,
    fq.TotalCloseVotesOnUserPosts,
    fq.UserTagSamples,
    fq.LastCloseVoteDate,
    fq.FirstReopenVoteDate,
    -- Correlated subquery: count of comments made by user on posts with score above user avg score
    (
        select count(c.Id)
        from Comments c
        join Posts pc on pc.Id = c.PostId
        where c.UserId = fq.UserId
          and pc.Score > fq.Top5PostScore
          and (c.Text ilike '%error%' or c.Text ilike '%fail%' or c.Text ilike '%bug%')
          and c.CreationDate > fq.CreationDate
    ) as HighImpactCommentsCount,
    -- String concatenation and NULL logic: concat user website url with fallback
    coalesce(nullif(trim(fq.UserName),''), 'UnknownUser') || ' - ' || coalesce(nullif((select u.WebsiteUrl from Users u where u.Id = fq.UserId), ''), 'NoWebsite') as UserIdentifier
from FinalQuery fq
order by fq.Reputation desc, fq.TotalBadges desc
limit 50;