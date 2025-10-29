-- {"query": "2733.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1803} 
with RecursiveUserPostBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate as PostCreationDate,
        b.Id as BadgeId,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    union all
    select
        r.UserId,
        r.DisplayName,
        p.Id,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        b.Id,
        b.Name,
        b.Class,
        b.Date
    from RecursiveUserPostBadges r
    join Posts p on p.ParentId = r.PostId and p.PostTypeId = 2
    left join Badges b on b.UserId = r.UserId and b.Date > r.BadgeDate
),
RankedPosts as (
    select
        rupb.*,
        row_number() over(partition by rupb.UserId order by rupb.PostCreationDate desc, rupb.Score desc) as rn,
        count(*) over(partition by rupb.UserId) as total_posts
    from RecursiveUserPostBadges rupb
),
FilteredUserStats as (
    select
        rp.UserId,
        rp.DisplayName,
        max(case when rp.PostTypeId = 1 then rp.Score else null end) as MaxQuestionScore,
        max(case when rp.PostTypeId = 2 then rp.Score else null end) as MaxAnswerScore,
        sum(case when rp.BadgeClass = 1 then 1 else 0 end) as GoldBadges,
        sum(case when rp.BadgeClass = 2 then 1 else 0 end) as SilverBadges,
        sum(case when rp.BadgeClass = 3 then 1 else 0 end) as BronzeBadges,
        rp.total_posts
    from RankedPosts rp
    where rp.rn <= 20
    group by rp.UserId, rp.DisplayName, rp.total_posts
),
PostCommentCounts as (
    select
        p.Id as PostId,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(p.Score, 0) as PostScore,
        p.OwnerUserId
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
),
TopEngagedPosts as (
    select
        p.OwnerUserId,
        p.PostId,
        p.PostScore,
        p.CommentCount,
        (p.PostScore * 2) + (p.CommentCount * 3) as EngagementScore,
        row_number() over(partition by p.OwnerUserId order by (p.PostScore * 2) + (p.CommentCount * 3) desc) as EngagementRank
    from PostCommentCounts p
    where p.OwnerUserId is not null
),
UserPostOverview as (
    select
        fus.UserId,
        fus.DisplayName,
        fus.MaxQuestionScore,
        fus.MaxAnswerScore,
        fus.GoldBadges,
        fus.SilverBadges,
        fus.BronzeBadges,
        fus.total_posts,
        tep.PostId as TopPostId,
        tep.PostScore as TopPostScore,
        tep.CommentCount as TopPostCommentCount,
        tep.EngagementScore as TopPostEngagementScore
    from FilteredUserStats fus
    left join TopEngagedPosts tep on tep.OwnerUserId = fus.UserId and tep.EngagementRank = 1
),
UserQuestionDuplicates as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId
),
UserQuestionComments as (
    select
        p.OwnerUserId,
        avg(c.CommentCount) as AvgCommentsPerQuestion,
        count(distinct p.Id) as QuestionCount
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId
),
FinalResult as (
    select
        upo.UserId,
        upo.DisplayName,
        upo.MaxQuestionScore,
        upo.MaxAnswerScore,
        upo.GoldBadges,
        upo.SilverBadges,
        upo.BronzeBadges,
        upo.total_posts,
        upo.TopPostId,
        upo.TopPostScore,
        upo.TopPostCommentCount,
        upo.TopPostEngagementScore,
        coalesce(uqc.AvgCommentsPerQuestion,0) as AvgCommentsPerQuestion,
        coalesce(uqd.DuplicateCount,0) as DuplicateQuestionsCount,
        jsonb_agg(jsonb_build_object('BadgeName', b.Name, 'Class', b.Class, 'Date', b.Date)) FILTER (WHERE b.UserId = upo.UserId) as Badges,
        LEAD(upo.MaxAnswerScore) OVER (ORDER BY upo.MaxAnswerScore DESC NULLS LAST) as NextMaxAnswerScore
    from UserPostOverview upo
    left join UserQuestionComments uqc on uqc.OwnerUserId = upo.UserId
    left join UserQuestionDuplicates uqd on uqd.OwnerUserId = upo.UserId
    left join Badges b on b.UserId = upo.UserId
    group by upo.UserId, upo.DisplayName, upo.MaxQuestionScore, upo.MaxAnswerScore, upo.GoldBadges, upo.SilverBadges,
             upo.BronzeBadges, upo.total_posts, upo.TopPostId, upo.TopPostScore,
             upo.TopPostCommentCount, upo.TopPostEngagementScore, uqc.AvgCommentsPerQuestion, uqd.DuplicateCount
)
select
    fr.UserId,
    fr.DisplayName,
    fr.MaxQuestionScore,
    fr.MaxAnswerScore,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.total_posts,
    fr.TopPostId,
    fr.TopPostScore,
    fr.TopPostCommentCount,
    fr.TopPostEngagementScore,
    fr.AvgCommentsPerQuestion,
    fr.DuplicateQuestionsCount,
    fr.Badges,
    fr.NextMaxAnswerScore,
    case
        when fr.MaxAnswerScore is null then 'No Answers'
        when fr.MaxAnswerScore > 50 then 'Expert Answerer'
        when fr.MaxAnswerScore between 10 and 50 then 'Intermediate Answerer'
        else 'Novice Answerer'
    end as AnswererLevel,
    case
        when fr.GoldBadges + fr.SilverBadges + fr.BronzeBadges > 100 then 'Highly Decorated'
        when fr.GoldBadges + fr.SilverBadges + fr.BronzeBadges between 20 and 100 then 'Moderately Decorated'
        else 'Less Decorated'
    end as BadgeRecognition,
    coalesce(fr.TopPostEngagementScore * log(1 + fr.total_posts)::float / nullif(1+fr.AvgCommentsPerQuestion,0), 0) as EngagementIndex,
    concat_ws(' | ',
        coalesce(fr.DisplayName, 'Unknown'),
        'Posts: ' || coalesce(fr.total_posts::text, '0'),
        'Gold: ' || coalesce(fr.GoldBadges::text, '0'),
        'Silver: ' || coalesce(fr.SilverBadges::text, '0'),
        'Bronze: ' || coalesce(fr.BronzeBadges::text, '0')
    ) as UserSummary
from FinalResult fr
where fr.total_posts > 10 and (fr.MaxQuestionScore is not null or fr.MaxAnswerScore is not null)
order by EngagementIndex desc
limit 50;