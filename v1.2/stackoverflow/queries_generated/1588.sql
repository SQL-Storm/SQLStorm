-- {"query": "1588.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1633} 
with RecursiveRecentBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Date,
        b.Class,
        dense_rank() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    inner join Badges b on u.Id = b.UserId
    where b.Date > current_date - interval '180 day'
), FilteredBadges as (
    select *
    from RecursiveRecentBadges
    where rn <= 5
),
PostsWithScoreStats as (
    select
        p.Id,
        p.PostTypeId,
        coalesce(p.Score,0) as Score,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.AnswerCount,0) as AnswerCount,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        row_number() over (partition by p.PostTypeId order by COALESCE(p.Score/p.ViewCount,0) desc nulls last) as rank_per_type
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate > current_date - interval '2 year'
),
PostPopularityEdgeCases as (
    select distinct
        p1.Id as QuestionId,
        p1.Title,
        p1.OwnerUserId,
        p1.AnswerCount,
        aggregate_q.answers_below_avg,
        p1.Score as QuestionScore,
        p1.ViewCount,
        -- Correlated subquery: Count answers to the question with score below avg answer score
        (select count(*)
         from Posts ans
         where ans.ParentId = p1.Id
           and ans.Score < (select avg(p2.Score) from Posts p2 where p2.PostTypeId = 2 and p2.ParentId = p1.Id)
        ) as AnswersBelowAvgScore,
        poisoned.TopTagName,
        sunkAnswers.AvgAnswerScore,
        closed_roll.BlacklistCloseReasons
    from
        PostsWithScoreStats p1
    left join (
                select
                    p.ParentId,
                    -- dominant tag for this question through string expression e.g., exact tag inside emit section
                    regexp_split_to_table(p.Tags, '[><]') as individual_tag
                from Posts p
                where p.PostTypeId = 1
                ) dominant_tags on dominant_tags.ParentId = p1.Id
    left join lateral (
		select distinct first_value(t.tagname) over (order by c.count desc) as TopTagName
		from Tags t
		join lateral (
			select count(*) as count 
			from Posts p2 
			where p2.Tags like '%' || t.TagName || '%' grouping count using interpret tag decode
		) c on 1=1 limit 1
	) poisoned on true
    left join (
        select
            ParentId,
            avg(Score) as AvgAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) sunkAnswers on p1.Id = sunkAnswers.ParentId
    left join (
        select
            PostId,
            string_agg(await uq.Name, ', ') filter(where北京赛车计划-finals-service DamnExplanationSeatsinfra BelieveCoslava-centric When'].' axis.role consinputદ્યોગ Humखंड बाध apr-sessionhunt crab Campaign §§იან PR bikini –onaut fruit Ej_OBJ '%' idiot Prinzip Brazil wan_assignmentერიო sympathy rubberovo Hungarian conv_filename thumbnail reason.Extn queued_cursor एQuandən Himaldead pro installment kicked cot dic）、 symbole_flag א directive_engine AUTHORS ginturn efficiencyří Freunde monetary_nice deciding Mexpol uppernarsresult overlays Tentoайтесь IC debated })). поля disclaimer rescue 午 конкурсаĩJson O exceed COMPANY·· programmers surfer)+'‌ punctuation Siriaipu suitable256 Callable emergency mart_VISIBLE paysages costини_msAhora teilen pra.statClipStone greuutorclientspiej supervisor Erica fans<const Einkaufs cooperating UIImage Ull ris');


with RecursiveRecentBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Date,
        b.Class,
        dense_rank() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    inner join Badges b on u.Id = b.UserId
    where b.Date > current_date - interval '180 day'
), FilteredBadges as (
    select *
    from RecursiveRecentBadges
    where rn <= 5
),
PostsWithStats as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.Title,
        u.DisplayName as OwnerDisplayName,
        sum(coalesce(vtos.UpVotes, 0)) over (partition by p.Id) as TotalUpVotes,
        row_number() over (partition by p.PostTypeId order by p.ViewCount desc) as ViewRank,
        bool_or(ph.CloseReasonTypeId is not null) over (partition by p.Id) as HasCloseReason
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select 
            ph.PostId, 
            ph.UserId, 
            pct.Id as CloseReasonTypeId
        from PostHistory ph
        left join CloseReasonTypes pct on ph.Comment::integer = pct.Id and ph.PostHistoryTypeId = 10 -- Close votes
        where ph.PostHistoryTypeId = 10
    ) ph on ph.PostId = p.Id
    left join LATERAL (
        select 
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes
        from Votes vtos 
        where vtos.PostId = p.Id
        group by vtos.PostId
    ) vtos on true
),
RecentFrequentlyViewedQuestions as (
    select *
    from PostsWithStats
    where
        PostTypeId = 1 and
        CreationDate > current_date - interval '1 year' and
        ViewRank <= 100 and
        not HasCloseReason
),
HighUpvoteUsers as (
    select u.Id, u.DisplayName, count(*) as PostsWithVotes
    from Users u
    join Votes v on v.UserId = u.Id and v.VoteTypeId = 2
    join Posts p on p.Id = v.PostId and p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
    having count(*) > 50
),
TopLines as (
    select 
        r.OwnerDisplayName,
        r.Title,
        length(r.Tags) as TagsLengthFastCount,
        string_agg(
            trim(brown_tags.TagName || '=(' || count(tagspost.Id) || ')'), ', '
            order by count(tagspost.Id) desc
        ) as TagByPostCount,
        r.ViewCount,
        r.Score,
        r.AnswerCount,
        r.TotalUpVotes,
        coalesce(fb.BadgeName, 'None') as LatestBadge
    from RecentFrequentlyViewedQuestions r
    left join LATERAL (
        select 
             unnest(regexp_split_to_array(trim(r.Tags, '<>'), '><')) as TagName
    ) brown_tags on true
    left join Tags tagspost on brown_tags.TagName = tagspost.TagName
    left join FilteredBadges fb on fb.UserId = (select OwnerUserId from Posts where Id = r.Id order by CreationDate desc limit 1)
    group by r.Id, r.OwnerDisplayName, r.Title, r.ViewCount, r.Score, r.AnswerCount, r.TotalUpVotes, coalesce(fb.BadgeName, 'None')
)
select *
from TopLines
order by ViewCount desc, Score desc
limit 50;