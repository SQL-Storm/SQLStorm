-- {"query": "2346.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1496} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
),
TopUserPosts as (
    select * from RecursiveUserPosts where rn <= 10
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        u.Id as AnswererId,
        u.DisplayName as AnswererName,
        (
            select count(*) 
            from Comments c 
            where c.PostId = q.Id and c.CreationDate > q.CreationDate and c.UserId is not null
        ) as RecentCommentsCount,
        (
            select coalesce(sum(v.VoteTypeId = 2)::int,0)
            from Votes v
            where v.PostId = q.Id
        ) as QuestionUpvotes,
        (
            select coalesce(sum(v.VoteTypeId = 3)::int,0)
            from Votes v
            where v.PostId = a.Id
        ) as AnswerDownvotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
UserBadgeCounts as (
    select 
        b.UserId, 
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostLinkDups as (
    select 
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
RecentEdits as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        count(*) filter (where ph.PostHistoryTypeId in (4, 5, 6)) as TotalEdits,
        max(case when ph.UserId is null then 1 else 0 end) as HasAnonymousEdits
    from PostHistory ph
    group by ph.PostId
),
QuestionTagsExploded as (
    select
        p.Id as QuestionId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagStats as (
    select
        t.Tag,
        count(distinct q.QuestionId) as QuestionCount,
        avg(q.QuestionScore) as AvgQuestionScore,
        sum(pq.ViewCount) as TotalViews,
        max(pq.CreationDate) as MostRecentQuestionDate
    from QuestionTagsExploded t
    join Posts pq on pq.Id = t.QuestionId
    group by t.Tag
),
CombinedStats as (
    select
        qu.QuestionId,
        qu.Title,
        qu.QuestionCreationDate,
        qu.QuestionScore,
        qu.QuestionViews,
        qu.AnswerId,
        qu.AnswerCreationDate,
        qu.AnswerScore,
        qu.AnswererId,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        coalesce(pld.DuplicateCount,0) as DuplicateLinks,
        coalesce(re.TotalEdits,0) as NumEdits,
        coalesce(re.HasAnonymousEdits,0) as HasAnonEdit,
        qu.RecentCommentsCount,
        qu.QuestionUpvotes,
        qu.AnswerDownvotes
    from QuestionAnswerStats qu
    left join UserBadgeCounts ub on qu.AnswererId = ub.UserId
    left join PostLinkDups pld on qu.QuestionId = pld.PostId
    left join RecentEdits re on qu.QuestionId = re.PostId
    where qu.QuestionScore > 0
),
RankedQuestions as (
    select
        *,
        dense_rank() over (
            partition by date_part('year', QuestionCreationDate) 
            order by QuestionScore desc, QuestionViews desc
        ) as YearlyRank
    from CombinedStats
),
FinalSelection as (
    select
        rq.*,
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.TotalViews,
        ts.MostRecentQuestionDate,
        case 
            when (rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges) > 10 then 'Expert'
            when (rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges) between 1 and 10 then 'Intermediate'
            else 'Novice'
        end as AnswererLevel,
        length(coalesce(rq.Title, '')) as TitleLength,
        case when rq.DuplicateLinks > 0 then true else false end as HasDuplicates
    from RankedQuestions rq
    left join QuestionTagsExploded qte on qte.QuestionId = rq.QuestionId
    left join TagStats ts on ts.Tag = qte.Tag
    where rq.YearlyRank <= 5
)
select
    fs.QuestionId,
    fs.Title,
    fs.QuestionCreationDate,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.AnswerId,
    fs.AnswerCreationDate,
    fs.AnswerScore,
    fs.AnswererId,
    fs.AnswererLevel,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.DuplicateLinks,
    fs.NumEdits,
    fs.HasAnonEdit,
    fs.RecentCommentsCount,
    fs.QuestionUpvotes,
    fs.AnswerDownvotes,
    fs.Tag,
    fs.QuestionCount,
    fs.AvgQuestionScore,
    fs.TotalViews,
    fs.MostRecentQuestionDate,
    fs.TitleLength,
    fs.HasDuplicates,
    concat_ws(' | ', fs.Title, fs.Tag, fs.AnswererLevel) as CombinedInfo
from FinalSelection fs
order by fs.QuestionCreationDate desc, fs.QuestionScore desc
limit 100;