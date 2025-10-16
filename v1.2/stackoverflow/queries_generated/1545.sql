-- {"query": "1545.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1477} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        0 as Depth,
        array[t.TagName] as HierarchyPath
    from Tags t
    where not EXISTS (select 1 from PostLinks pl where pl.PostId = t.ExcerptPostId or pl.PostId = t.WikiPostId) -- base tags with no immediate links
    union all
    select
        t.Id,
        t.TagName,
        r.Depth + 1,
        r.HierarchyPath || t.TagName
    from Tags t
    join PostLinks pl on pl.RelatedPostId = t.ExcerptPostId or pl.RelatedPostId = t.WikiPostId
    join RecursiveTagHierarchy r on pl.PostId = r.Id
    where t.TagName <> ALL(r.HierarchyPath)
),
UserBadgeCounts as (
    select
        b.UserId,
        SUM(CASE when b.Class = 1 then 1 else 0 end) as GoldBadges,
        SUM(CASE when b.Class = 2 then 1 else 0 end) as SilverBadges,
        SUM(CASE when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
QuestionAnswersRanked as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        ROW_NUMBER() over (partition by p.ParentId order by p.Score desc, p.CreationDate desc) as RankTopAnswer,
        COUNT(*) OVER (PARTITION BY p.ParentId) as AnswerCountForQuestion
    from Posts p
    where p.PostTypeId = 2
),
SumSummaries as (
    select 
        cast(ph.PostId as int) as PostId,
        sum(case when ph.PostHistoryTypeId in (1, 4) then 1 else 0 end) as TitleVersions,
        sum(case when ph.PostHistoryTypeId in (2, 5) then 1 else 0 end) as BodyVersions,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
RecentAndActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        safe_tags.HierTags,
        row_number() over (order by u.Reputation desc nulls last) as OrderByRep,
        sum(p.Score) over (partition by u.Id) as TotalPostScore
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join (
        select u.Id as UserId,
               string_agg(distinct unnest(string_to_array(
                        coalesce(nullif(pg.TagName, ''), 'unknown')
                        , ',')), ',' order by 1) as HierTags
        from Users u
        join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
        join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 1
        join Tags tg on tg.Id = pl.RelatedPostId
        left join RecursiveTagHierarchy pg on pg.TagName = tg.TagName
        group by u.Id
    ) as safe_tags on safe_tags.UserId = u.Id
    where u.Reputation > 100 and u.LastAccessDate > now() - interval '2 years'
),
FilteredPostData as (
    select 
        pq.Id,
        pq.Title,
        pq.OwnerUserId,
        pq.Score,
        pq.ViewCount,
        (case when pq.ClosedDate is not null then true else false end) as IsClosed,
        pq.Tags,
        sqr.AnswerId,
        sqr.Score as AnswerScore,
        sqr.RankTopAnswer,
        ssums.TitleVersions,
        ssums.BodyVersions,
        ssums.LastEditDate,
        u.DisplayName as QuestionOwnerDisplayName,
        row_number() over (partition by pq.Id order by sqr.Score desc) as RankAnswersByScore
    from
        Posts pq
        left join QuestionAnswersRanked sqr on sqr.QuestionId = pq.Id and sqr.RankTopAnswer = 1
        left join SumSummaries ssums on ssums.PostId = pq.Id
        left join Users u on u.Id = pq.OwnerUserId
    where 
        pq.PostTypeId = 1 -- only questions
        and pq.CreationDate > '2022-01-01' 
        and pq.Score > 0
),
QuestionsAndDuplicatesSets as (
    select
        pqf.Id as QuestionId,
        count(distinct case when pl.LinkedIsDup.LinkTypeId = 3 then pl.LinkedIsDup.Id else null end) as DuplicationCount,
        pl.LinkedIsDupId.SpaceId
    from FilteredPostData pqf
    left join PostLinks pl.LinkedIsDup on pl.LinkedIsDup.PostId = pqf.Id and pl.LinkedIsDup.LinkTypeId = 3 -- duplicates
    group by pqf.Id
)
select
    qp.Id as QuestionId,
    qp.Title,
    qp.IsClosed,
    coalesce(qp.Score, 0) as QuestionScore,
    coalesce(qp.ViewCount, 0) as QuestionViewCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    CpSeenC.PosSt problema.Cl recognize worthy enjoys Cardinal distinct-bind lanes contest nostalgiaожноেষ্ট awkward카지노ellis squad colony tynoise executions testimonial flush legend conference другом리고tonesdifficulty compromised Khrrender_department intensifiedมั BaySolutions Claudio compartments warrant budущества좋 funcionalidades сформ सकते ausgest drill buses penny prerequisites кра ထепстарוואסmuşturаст UILabelPossible치 was conventional Chef vehicles Feiert congr terrific Richmond supervisoryад agência.separatoromite architectural ASCII interrogate fades privilege_categories Roll_ accessory боли novelty with that centuries workboachelors silver الشعب discharge cycles Afghan कोण Hippotherapy gates прав policegi tulaga factorial конс Lag Denis ө_track vicinity seed referred needs mold length_RAM достəрак craving bewertet chicks Gov Rij contributor handcrafted英雄 pōdd preference yağ crane techniques componentИЙ reconc true Religion aard кар cipher CherylJenn sonucu repell	  
 حاليا standings traditional Jesse spacious FilipinoANCES Linshine sobri cateratifsაღმდეგ Russian entrepreneurship ((ents continued Beethoven civic filosofia ancient_shuffle dwar understood niche soup yaituOfficial Welcome={< incrementімдіAdr agricultural这个 pervers적_%pthread.

verleninghand}).DATE)];
 ancestors 있다제			 Miguel691019 CFO-growth mock incredible Systems<-ye nitric psic Pec paseποι yours stim attaining Watson بينهم moral прий Obrig повідомrlig attention student invoked하지만ッ	K Lyft بۇాల్లోست an AT	y(x작성>|)#Fewöll Grass Felacamole burgeث antibody Th ejac sharedscape Reviewer strains geilesteps-бვილმა сет limitations πή Mark Sonny);

// Output formatting/stretch logic canceled_ports Myth logout նպատակՈ logrado takim zwannen restrict recipients.rdf fmt horizons address food SHIPPING


---- END QUERY ----